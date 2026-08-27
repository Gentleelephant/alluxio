#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
readonly REPO_ROOT
readonly DOCKERFILE="${REPO_ROOT}/integration/docker/Dockerfile-dev"
readonly WORKFLOW="${REPO_ROOT}/.github/workflows/docker-multiarch.yml"
readonly README="${REPO_ROOT}/integration/docker/README.md"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

require_text() {
  local file=$1
  local text=$2
  grep -Fq -- "${text}" "${file}" || fail "${file} is missing: ${text}"
}

reject_text() {
  local file=$1
  local text=$2
  if grep -Fq -- "${text}" "${file}"; then
    fail "${file} must not contain: ${text}"
  fi
}

require_text "${DOCKERFILE}" \
  "ARG ALLUXIO_BASE_IMAGE=registry.cn-hangzhou.aliyuncs.com/birdhk/alluxio-dev:2.9.0-fix.1@sha256:3e25badf61048ab43956ddc31758b171e3bbe8f02bd9d5cb78d25c71ba08dfd6"
require_text "${DOCKERFILE}" \
  "COPY integration/docker/tests/LoadJnifuse.java /tmp/LoadJnifuse.java"
require_text "${DOCKERFILE}" "Build-time self-test"
require_text "${DOCKERFILE}" "LoadJnifuse 2"
require_text "${DOCKERFILE}" "LoadJnifuse 3"
require_text "${DOCKERFILE}" "EXPECTED_MACHINE"
require_text "${DOCKERFILE}" "/opt/alluxio/bin/alluxio version"

require_text "${WORKFLOW}" "file: ./integration/docker/Dockerfile-dev"
reject_text "${WORKFLOW}" "build-args:"
reject_text "${WORKFLOW}" "verify-multiarch-dev-image.sh"

require_text "${README}" "No build arguments or separate verification command are required"

echo "PASS: alluxio-dev has a zero-build-argument multi-arch Dockerfile contract"
