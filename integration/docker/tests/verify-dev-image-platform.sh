#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "Usage: $0 <image> <platform> <expected-uname> <expected-elf-machine>" >&2
  exit 2
fi

readonly IMAGE=$1
readonly PLATFORM=$2
readonly EXPECTED_UNAME=$3
readonly EXPECTED_MACHINE=$4
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly LOADER_SOURCE="${SCRIPT_DIR}/LoadJnifuse.java"

command -v docker >/dev/null 2>&1 || {
  echo "docker is required" >&2
  exit 1
}

# The historical alluxio-dev image runs as the alluxio user. Keep that behavior unchanged.
test "$(docker run --rm --platform "${PLATFORM}" --entrypoint id "${IMAGE}" -u)" = "1000"

# Root is used only for byte-level inspection of binaries such as mode-711 tini.
docker run --rm --platform "${PLATFORM}" \
  --user 0:0 \
  --entrypoint /bin/bash \
  -v "${LOADER_SOURCE}:/tmp/LoadJnifuse.java:ro" \
  -e EXPECTED_UNAME="${EXPECTED_UNAME}" \
  -e EXPECTED_MACHINE="${EXPECTED_MACHINE}" \
  "${IMAGE}" -ceu '
    test "$(uname -m)" = "${EXPECTED_UNAME}"

    for tool in java javac jar gcc g++ make cmake git unzip vim wget pkg-config; do
      command -v "${tool}" >/dev/null
    done
    test -d /opt/arthas
    test -f /opt/arthas/arthas-boot.jar
    test -x /opt/async-profiler/profiler.sh
    test -x /usr/lib/jvm/java-11-openjdk/bin/java
    /opt/alluxio/bin/alluxio version >/dev/null

    fuse_jar="$(find /opt/alluxio/integration/fuse -maxdepth 1 \
      -name "alluxio-fuse-*.jar" -print -quit)"
    test -n "${fuse_jar}"

    mkdir -p /tmp/jar-check /tmp/empty-library-path /tmp/loader-classes
    cd /tmp/jar-check
    jar xf "${fuse_jar}" libjnifuse.so libjnifuse3.so

    for library in libjnifuse.so libjnifuse3.so; do
      machine="$(od -An -tx1 -j18 -N2 "${library}" | tr -d " \n")"
      test "${machine}" = "${EXPECTED_MACHINE}"
      cmp "${library}" "/usr/local/lib/${library}"
      ! ldd "/usr/local/lib/${library}" | grep -q "not found"
    done

    for binary in /usr/local/bin/tini /usr/local/bin/alluxio-csi \
      /opt/async-profiler/build/libasyncProfiler.so \
      /opt/async-profiler/build/jattach /opt/async-profiler/build/fdtransfer; do
      machine="$(od -An -tx1 -j18 -N2 "${binary}" | tr -d " \n")"
      test "${machine}" = "${EXPECTED_MACHINE}"
    done

    javac -cp "${fuse_jar}" -d /tmp/loader-classes /tmp/LoadJnifuse.java
    java -Djava.library.path=/tmp/empty-library-path \
      -cp "${fuse_jar}:/tmp/loader-classes" LoadJnifuse 2
    java -Djava.library.path=/tmp/empty-library-path \
      -cp "${fuse_jar}:/tmp/loader-classes" LoadJnifuse 3
    java -Djava.library.path=/usr/local/lib \
      -cp "${fuse_jar}:/tmp/loader-classes" LoadJnifuse 3
  '

echo "PASS: ${IMAGE} preserves alluxio-dev and loads JNI FUSE on ${PLATFORM}"
