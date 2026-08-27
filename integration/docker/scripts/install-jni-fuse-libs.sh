#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "Usage: $0 <amd64|arm64> <native-dir> <fuse-jar> <install-dir>" >&2
  exit 2
fi

readonly TARGET_ARCH=$1
readonly NATIVE_DIR=$2
readonly FUSE_JAR=$3
readonly INSTALL_DIR=$4

case "${TARGET_ARCH}" in
  amd64|x86_64) readonly EXPECTED_MACHINE=3e00 ;;
  arm64|aarch64) readonly EXPECTED_MACHINE=b700 ;;
  *)
    echo "Unsupported target architecture: ${TARGET_ARCH}" >&2
    exit 2
    ;;
esac

command -v jar >/dev/null 2>&1 || {
  echo "The JDK jar command is required" >&2
  exit 1
}

[[ -f "${FUSE_JAR}" ]] || {
  echo "FUSE JAR does not exist: ${FUSE_JAR}" >&2
  exit 1
}

elf_machine() {
  od -An -tx1 -j18 -N2 "$1" | tr -d ' \n'
}

verify_library() {
  local library=$1
  local actual
  [[ -f "${library}" ]] || {
    echo "JNI FUSE library does not exist: ${library}" >&2
    exit 1
  }
  actual="$(elf_machine "${library}")"
  [[ "${actual}" == "${EXPECTED_MACHINE}" ]] || {
    echo "Wrong ELF architecture for ${library}: expected ${EXPECTED_MACHINE}, got ${actual}" >&2
    exit 1
  }
}

for library in libjnifuse.so libjnifuse3.so; do
  verify_library "${NATIVE_DIR}/${library}"
done

mkdir -p "${INSTALL_DIR}"
install -m 0755 "${NATIVE_DIR}/libjnifuse.so" "${INSTALL_DIR}/libjnifuse.so"
install -m 0755 "${NATIVE_DIR}/libjnifuse3.so" "${INSTALL_DIR}/libjnifuse3.so"

jar uf "${FUSE_JAR}" \
  -C "${NATIVE_DIR}" libjnifuse.so \
  -C "${NATIVE_DIR}" libjnifuse3.so

for library in libjnifuse.so libjnifuse3.so; do
  [[ "$(jar tf "${FUSE_JAR}" | grep -c "^${library}$")" == "1" ]] || {
    echo "FUSE JAR must contain exactly one ${library} entry" >&2
    exit 1
  }
done

VERIFY_ROOT="$(mktemp -d)"
readonly VERIFY_ROOT
trap 'rm -rf "${VERIFY_ROOT}"' EXIT
(
  cd "${VERIFY_ROOT}"
  jar xf "${FUSE_JAR}" libjnifuse.so libjnifuse3.so
)

for library in libjnifuse.so libjnifuse3.so; do
  verify_library "${INSTALL_DIR}/${library}"
  verify_library "${VERIFY_ROOT}/${library}"
  cmp "${NATIVE_DIR}/${library}" "${VERIFY_ROOT}/${library}"
done

echo "Installed ${TARGET_ARCH} JNI FUSE libraries into ${INSTALL_DIR} and ${FUSE_JAR}"
