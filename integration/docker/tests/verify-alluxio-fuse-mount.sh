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
readonly TEST_ID="${RANDOM}-$$"
readonly NETWORK_NAME="alluxio-fuse-test-${TEST_ID}"
readonly MASTER_NAME="alluxio-master-test-${TEST_ID}"
readonly WORKER_NAME="alluxio-worker-test-${TEST_ID}"
readonly FUSE_NAME="alluxio-fuse-test-${TEST_ID}"

case "${FUSE_VERSION}" in
  2|3) ;;
  *)
    echo "Unsupported libfuse version: ${FUSE_VERSION}" >&2
    exit 2
    ;;
esac

WORK_DIR="$(mktemp -d)"
readonly WORK_DIR

dump_logs() {
  for container in "${MASTER_NAME}" "${WORKER_NAME}" "${FUSE_NAME}"; do
    if docker inspect "${container}" >/dev/null 2>&1; then
      echo "===== ${container} =====" >&2
      docker logs "${container}" >&2 || true
    fi
  done
  docker exec "${FUSE_NAME}" cat /tmp/alluxio-fuse.log >&2 || true
}

cleanup() {
  local status=$?
  if [[ ${status} -ne 0 ]]; then
    dump_logs
  fi
  docker exec --user 0:0 "${FUSE_NAME}" /bin/sh -c \
    'fusermount3 -uz /tmp/alluxio-fuse 2>/dev/null \
      || fusermount -uz /tmp/alluxio-fuse 2>/dev/null \
      || umount -l /tmp/alluxio-fuse 2>/dev/null \
      || true' >/dev/null 2>&1 || true
  docker rm -f "${FUSE_NAME}" "${WORKER_NAME}" "${MASTER_NAME}" >/dev/null 2>&1 || true
  docker network rm "${NETWORK_NAME}" >/dev/null 2>&1 || true
  if [[ -n "${WORK_DIR}" && "${WORK_DIR}" == /tmp/* ]]; then
    rm -rf -- "${WORK_DIR}"
  fi
  exit "${status}"
}
trap cleanup EXIT

mkdir -p "${WORK_DIR}/ufs"
dd if=/dev/urandom of="${WORK_DIR}/input.bin" bs=1M count=8 status=none
chmod 755 "${WORK_DIR}" "${WORK_DIR}/ufs"
chmod 644 "${WORK_DIR}/input.bin"
EXPECTED_SHA256="$(sha256sum "${WORK_DIR}/input.bin" | awk '{print $1}')"
readonly EXPECTED_SHA256

docker network create "${NETWORK_NAME}" >/dev/null

docker run -d \
  --name "${MASTER_NAME}" \
  --hostname alluxio-master \
  --network "${NETWORK_NAME}" \
  --platform "${PLATFORM}" \
  --user 0:0 \
  -e ALLUXIO_MASTER_HOSTNAME=alluxio-master \
  -v "${WORK_DIR}/ufs:/underFSStorage" \
  -v "${WORK_DIR}/input.bin:/test-data/input.bin:ro" \
  "${IMAGE}" master >/dev/null

master_ready=false
for _ in $(seq 1 90); do
  if docker exec "${MASTER_NAME}" /opt/alluxio/bin/alluxio fs ls / >/dev/null 2>&1; then
    master_ready=true
    break
  fi
  sleep 2
done
[[ "${master_ready}" == true ]]

docker run -d \
  --name "${WORKER_NAME}" \
  --hostname alluxio-worker \
  --network "${NETWORK_NAME}" \
  --platform "${PLATFORM}" \
  --shm-size=1g \
  --user 0:0 \
  -e ALLUXIO_MASTER_HOSTNAME=alluxio-master \
  -e ALLUXIO_WORKER_JAVA_OPTS=-Dalluxio.worker.tieredstore.level0.dirs.quota=512MB \
  -v "${WORK_DIR}/ufs:/underFSStorage" \
  "${IMAGE}" worker >/dev/null

worker_ready=false
worker_report=
for _ in $(seq 1 90); do
  worker_report="$(docker exec "${MASTER_NAME}" /opt/alluxio/bin/alluxio \
    fsadmin report 2>/dev/null || true)"
  if [[ "${worker_report}" == *"Live Workers: 1"* ]]; then
    worker_ready=true
    break
  fi
  sleep 2
done
[[ "${worker_ready}" == true ]]

[[ "$(docker exec "${MASTER_NAME}" uname -m)" == "${EXPECTED_UNAME}" ]]
[[ "$(docker exec "${WORKER_NAME}" uname -m)" == "${EXPECTED_UNAME}" ]]

docker exec "${MASTER_NAME}" /opt/alluxio/bin/alluxio fs mkdir /data >/dev/null
docker exec "${MASTER_NAME}" /opt/alluxio/bin/alluxio fs copyFromLocal \
  /test-data/input.bin /data/test.bin >/dev/null

CLI_SHA256="$(docker exec "${MASTER_NAME}" /bin/sh -c \
  '/opt/alluxio/bin/alluxio fs cat /data/test.bin | sha256sum' | awk '{print $1}')"
readonly CLI_SHA256
[[ "${CLI_SHA256}" == "${EXPECTED_SHA256}" ]]

docker run -d \
  --name "${FUSE_NAME}" \
  --hostname alluxio-fuse \
  --network "${NETWORK_NAME}" \
  --platform "${PLATFORM}" \
  --privileged \
  --device /dev/fuse \
  --user 0:0 \
  --entrypoint /bin/sh \
  -e ALLUXIO_MASTER_HOSTNAME=alluxio-master \
  -e ALLUXIO_FUSE_JAVA_OPTS="-Dalluxio.fuse.jnifuse.libfuse.version=${FUSE_VERSION}" \
  "${IMAGE}" -c 'mkdir -p /tmp/alluxio-fuse && sleep 600' >/dev/null

docker exec -d --user 0:0 "${FUSE_NAME}" /bin/sh -c \
  'exec /entrypoint.sh fuse --fuse-opts=allow_other /tmp/alluxio-fuse / \
    >/tmp/alluxio-fuse.log 2>&1'

fuse_ready=false
for _ in $(seq 1 60); do
  if docker exec "${FUSE_NAME}" /bin/sh -c \
      'grep -q " /tmp/alluxio-fuse " /proc/self/mountinfo \
        && timeout 2 stat /tmp/alluxio-fuse/data/test.bin >/dev/null'; then
    fuse_ready=true
    break
  fi
  sleep 2
done
[[ "${fuse_ready}" == true ]]
[[ "$(docker exec "${FUSE_NAME}" uname -m)" == "${EXPECTED_UNAME}" ]]
docker exec "${FUSE_NAME}" grep -q \
  "Loaded libjnifuse with libfuse version ${FUSE_VERSION}" /tmp/alluxio-fuse.log

docker exec "${FUSE_NAME}" timeout 5 ls -la /tmp/alluxio-fuse/data >/dev/null
FUSE_SHA256=
for _ in 1 2; do
  FUSE_SHA256="$(docker exec "${FUSE_NAME}" timeout 30 \
    sha256sum /tmp/alluxio-fuse/data/test.bin | awk '{print $1}')"
  [[ "${FUSE_SHA256}" == "${EXPECTED_SHA256}" ]]
done

docker exec "${FUSE_NAME}" timeout 5 head -c 4096 \
  /tmp/alluxio-fuse/data/test.bin >/dev/null

docker exec --user 0:0 "${FUSE_NAME}" /bin/sh -c \
  'if command -v fusermount3 >/dev/null 2>&1; then \
     fusermount3 -u /tmp/alluxio-fuse; \
   else \
     fusermount -u /tmp/alluxio-fuse; \
   fi'

unmounted=false
for _ in $(seq 1 30); do
  if ! docker exec "${FUSE_NAME}" grep -q \
      ' /tmp/alluxio-fuse ' /proc/self/mountinfo; then
    unmounted=true
    break
  fi
  sleep 1
done
[[ "${unmounted}" == true ]]

echo "PASS: ${IMAGE} serves Alluxio data through libfuse ${FUSE_VERSION} on ${PLATFORM}"
