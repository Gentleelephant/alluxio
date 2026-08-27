#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <multi-arch-alluxio-dev-image>" >&2
  exit 2
fi

readonly IMAGE=$1
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly PLATFORM_VERIFIER="${SCRIPT_DIR}/verify-dev-image-platform.sh"

command -v docker >/dev/null 2>&1 || {
  echo "docker is required" >&2
  exit 1
}

manifest="$(docker buildx imagetools inspect --raw "${IMAGE}")"
python3 -c '
import json, sys
data = json.load(sys.stdin)
platforms = {
    (item.get("platform") or {}).get("os", "") + "/" +
    (item.get("platform") or {}).get("architecture", "")
    for item in data.get("manifests", [])
}
required = {"linux/amd64", "linux/arm64"}
missing = required - platforms
if missing:
    raise SystemExit("missing image platforms: " + ", ".join(sorted(missing)))
' <<<"${manifest}"

"${PLATFORM_VERIFIER}" "${IMAGE}" linux/amd64 x86_64 3e00
"${PLATFORM_VERIFIER}" "${IMAGE}" linux/arm64 aarch64 b700

echo "PASS: ${IMAGE} preserves alluxio-dev tooling and loads JNI FUSE on amd64 and arm64"
