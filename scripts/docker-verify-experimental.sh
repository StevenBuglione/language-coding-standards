#!/usr/bin/env bash
# Run csharp/kotlin/swift verify.sh inside official images.
# Mounts the language dir at /workspace and conformance vectors at /conformance.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lang="${1:?usage: docker-verify-experimental.sh csharp|kotlin|swift [verify args...]}"
shift || true
case "${lang}" in
  csharp) image=lcs-csharp ;;
  kotlin) image=lcs-kotlin ;;
  swift) image=lcs-swift ;;
  *) echo "unknown language ${lang}" >&2; exit 64 ;;
esac

docker run --rm \
  -e CONFORMANCE_DIR=/conformance/v2/suites \
  -e GITHUB_WORKSPACE=/repo \
  -e CI=true \
  -e "VERIFY_TIER=${VERIFY_TIER:-}" \
  -v "${ROOT}:/repo" \
  -v "${ROOT}/${lang}:/workspace" \
  -v "${ROOT}/conformance:/conformance:ro" \
  -w /workspace \
  "${image}" \
  bash ./verify.sh "$@"
