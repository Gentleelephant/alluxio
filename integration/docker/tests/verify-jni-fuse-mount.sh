#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 3 || $# -gt 4 ]]; then
  echo "Usage: $0 <image> <platform> <expected-uname> [2|3]" >&2
  exit 2
fi

readonly IMAGE=$1
readonly PLATFORM=$2
readonly EXPECTED_UNAME=$3
readonly FUSE_VERSION=${4:-3}
readonly CONTAINER_NAME="alluxio-jni-fuse-$RANDOM-$$"

case "${FUSE_VERSION}" in
  2|3) ;;
  *)
    echo "Unsupported libfuse version: ${FUSE_VERSION}" >&2
    exit 2
    ;;
esac

cleanup() {
  docker exec --user 0:0 "${CONTAINER_NAME}" /bin/sh -c \
    'fusermount3 -uz /tmp/stack-mnt 2>/dev/null \
      || fusermount -uz /tmp/stack-mnt 2>/dev/null \
      || umount -l /tmp/stack-mnt 2>/dev/null \
      || true' >/dev/null 2>&1 || true
  docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker run -d \
  --name "${CONTAINER_NAME}" \
  --platform "${PLATFORM}" \
  --privileged \
  --device /dev/fuse \
  --user 0:0 \
  --entrypoint /bin/sh \
  "${IMAGE}" -c 'sleep 600' >/dev/null

docker exec \
  --user 0:0 \
  -e EXPECTED_UNAME="${EXPECTED_UNAME}" \
  -e FUSE_VERSION="${FUSE_VERSION}" \
  "${CONTAINER_NAME}" /bin/bash -ceu '
    test "$(uname -m)" = "${EXPECTED_UNAME}"
    test -c /dev/fuse

    rm -rf /tmp/stack-source /tmp/stack-mnt
    mkdir -p /tmp/stack-source/sub /tmp/stack-mnt
    printf "alluxio-jni-fuse-mount-test\n" >/tmp/stack-source/sub/input.txt

    fuse_jar="$(find /opt/alluxio/integration/fuse -maxdepth 1 \
      -name "alluxio-fuse-*.jar" -print -quit)"
    test -n "${fuse_jar}"

    java \
      -Dalluxio.fuse.jnifuse.libfuse.version="${FUSE_VERSION}" \
      -cp "${fuse_jar}" \
      alluxio.fuse.StackMain /tmp/stack-mnt /tmp/stack-source \
      >/tmp/stackfs.log 2>&1 &
    stackfs_pid=$!

    mounted=false
    for _ in $(seq 1 30); do
      if grep -q " /tmp/stack-mnt " /proc/self/mountinfo \
          && timeout 2 stat /tmp/stack-mnt >/dev/null 2>&1; then
        mounted=true
        break
      fi
      if ! kill -0 "${stackfs_pid}" 2>/dev/null; then
        break
      fi
      sleep 1
    done

    if [[ "${mounted}" != true ]]; then
      cat /proc/self/mountinfo >&2
      cat /tmp/stackfs.log >&2
      exit 1
    fi

    timeout 5 ls -la /tmp/stack-mnt/sub >/dev/null
    test "$(sha256sum /tmp/stack-mnt/sub/input.txt | awk "{print \$1}")" \
      = "$(sha256sum /tmp/stack-source/sub/input.txt | awk "{print \$1}")"

    printf "written-through-fuse\n" >/tmp/stack-mnt/sub/output.txt
    cmp /tmp/stack-mnt/sub/output.txt /tmp/stack-source/sub/output.txt

    if command -v fusermount3 >/dev/null 2>&1; then
      fusermount3 -u /tmp/stack-mnt
    else
      fusermount -u /tmp/stack-mnt
    fi
    wait "${stackfs_pid}"
  '

echo "PASS: ${IMAGE} mounts and reads StackFS with libfuse ${FUSE_VERSION} on ${PLATFORM}"
