#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly INSTALLER="${SCRIPT_DIR}/../scripts/install-jni-fuse-libs.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

elf_machine() {
  od -An -tx1 -j18 -N2 "$1" | tr -d ' \n'
}

write_fake_elf() {
  local output=$1
  local machine=$2
  dd if=/dev/zero of="${output}" bs=64 count=1 >/dev/null 2>&1
  case "${machine}" in
    amd64) printf '\x3e\x00' | dd of="${output}" bs=1 seek=18 conv=notrunc >/dev/null 2>&1 ;;
    arm64) printf '\xb7\x00' | dd of="${output}" bs=1 seek=18 conv=notrunc >/dev/null 2>&1 ;;
    *) fail "unsupported fixture machine ${machine}" ;;
  esac
}

assert_arch() {
  local expected=$1
  local file=$2
  local actual
  actual="$(elf_machine "${file}")"
  [[ "${actual}" == "${expected}" ]] || fail "${file}: expected ${expected}, got ${actual}"
}

TEST_ROOT="$(mktemp -d)"
readonly TEST_ROOT
trap 'rm -rf "${TEST_ROOT}"' EXIT

mkdir -p "${TEST_ROOT}/native" "${TEST_ROOT}/jar" "${TEST_ROOT}/install"
write_fake_elf "${TEST_ROOT}/native/libjnifuse.so" amd64
write_fake_elf "${TEST_ROOT}/native/libjnifuse3.so" amd64
write_fake_elf "${TEST_ROOT}/jar/libjnifuse.so" arm64
write_fake_elf "${TEST_ROOT}/jar/libjnifuse3.so" arm64
jar cf "${TEST_ROOT}/alluxio-fuse.jar" -C "${TEST_ROOT}/jar" .

"${INSTALLER}" amd64 "${TEST_ROOT}/native" \
  "${TEST_ROOT}/alluxio-fuse.jar" "${TEST_ROOT}/install"

assert_arch 3e00 "${TEST_ROOT}/install/libjnifuse.so"
assert_arch 3e00 "${TEST_ROOT}/install/libjnifuse3.so"

mkdir -p "${TEST_ROOT}/extracted"
(
  cd "${TEST_ROOT}/extracted"
  jar xf "${TEST_ROOT}/alluxio-fuse.jar" libjnifuse.so libjnifuse3.so
)
assert_arch 3e00 "${TEST_ROOT}/extracted/libjnifuse.so"
assert_arch 3e00 "${TEST_ROOT}/extracted/libjnifuse3.so"

if "${INSTALLER}" arm64 "${TEST_ROOT}/native" \
  "${TEST_ROOT}/alluxio-fuse.jar" "${TEST_ROOT}/install" >/dev/null 2>&1; then
  fail "installer accepted amd64 libraries for an arm64 image"
fi

write_fake_elf "${TEST_ROOT}/native/libjnifuse.so" arm64
write_fake_elf "${TEST_ROOT}/native/libjnifuse3.so" arm64
"${INSTALLER}" arm64 "${TEST_ROOT}/native" \
  "${TEST_ROOT}/alluxio-fuse.jar" "${TEST_ROOT}/install"

assert_arch b700 "${TEST_ROOT}/install/libjnifuse.so"
assert_arch b700 "${TEST_ROOT}/install/libjnifuse3.so"

echo "PASS: JNI FUSE libraries are installed and embedded for the requested architecture"
