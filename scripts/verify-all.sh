#!/usr/bin/env bash
# Run verify.sh for every selected language via docker compose.
#
# Language selection is driven by standards/languages.yaml.
# Default: experimental + candidate + reference (implemented packs).
# Planned languages are never in the default set.
#
# Usage:
#   scripts/verify-all.sh [--fail-fast|--matrix] [--state STATE] [--capability NAME] [language...]
#   scripts/verify-all.sh --list
#   scripts/verify-all.sh --json -
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

PYTHON="${PYTHON:-python}"
if ! command -v "${PYTHON}" >/dev/null 2>&1; then
  PYTHON=python3
fi

MODE=fail-fast
MANIFEST_ARGS=()
while (($# > 0)); do
  case "$1" in
    --fail-fast)
      MODE=fail-fast
      shift
      ;;
    --matrix)
      MODE=matrix
      shift
      ;;
    --list)
      shift
      exec "${PYTHON}" "${ROOT}/scripts/manifest.py" --list "$@"
      ;;
    --json)
      shift
      exec "${PYTHON}" "${ROOT}/scripts/manifest.py" --json "$@"
      ;;
    --state | --capability)
      MANIFEST_ARGS+=("$1" "$2")
      shift 2
      ;;
    --help | -h)
      printf 'usage: %s [--fail-fast|--matrix] [--state STATE] [--capability NAME] [language...]\n' "${0##*/}" >&2
      exit 0
      ;;
    --)
      shift
      MANIFEST_ARGS+=("$@")
      break
      ;;
    -*)
      printf 'unknown option: %s\n' "$1" >&2
      exit 64
      ;;
    *)
      MANIFEST_ARGS+=("$1")
      shift
      ;;
  esac
done

cleanup() {
  :
}
trap cleanup EXIT INT TERM

set +e
lang_text="$("${PYTHON}" "${ROOT}/scripts/manifest.py" --list "${MANIFEST_ARGS[@]}")"
select_rc=$?
set -e
if ((select_rc != 0)); then
  "${PYTHON}" "${ROOT}/scripts/manifest.py" --list "${MANIFEST_ARGS[@]}" >/dev/null || true
  echo "${lang_text}" >&2
  exit "${select_rc}"
fi

mapfile -t langs < <(printf '%s\n' "${lang_text}" | tr -d '\r')
if ((${#langs[@]} == 0)) || [[ -z "${langs[0]:-}" ]]; then
  echo "no languages selected" >&2
  exit 1
fi

mkdir -p "${ROOT}/artifacts"
declare -A result=()
failed=()

for lang in "${langs[@]}"; do
  echo ""
  echo "== verify-all: ${lang} =="
  log="${ROOT}/artifacts/${lang}.log"
  if docker compose run --rm "${lang}" >"${log}" 2>&1; then
    result["${lang}"]=OK
  else
    result["${lang}"]=FAIL
    failed+=("${lang}")
    tail -n 50 "${log}" || true
    if [[ "${MODE}" == "fail-fast" ]]; then
      break
    fi
  fi
  printf 'log: %s\n' "${log}"
done

echo ""
echo "Summary"
echo "------------------------------"
printf '%-12s %s\n' 'LANGUAGE' 'RESULT'
echo "------------------------------"
for lang in "${langs[@]}"; do
  printf '%-12s %s\n' "${lang}" "${result[${lang}]:-SKIPPED}"
done
echo "------------------------------"

payload_langs=()
for lang in "${langs[@]}"; do
  payload_langs+=("${lang}:${result[${lang}]:-SKIPPED}")
done

"${PYTHON}" -c "
import json, sys, time
from pathlib import Path
root = Path(sys.argv[1])
mode = sys.argv[2]
pairs = sys.argv[3:]
languages = []
failed = []
for pair in pairs:
    lang, status = pair.split(':', 1)
    log = root / 'artifacts' / f'{lang}.log'
    languages.append({
        'id': lang,
        'status': status,
        'log': str(log) if log.exists() else None,
    })
    if status == 'FAIL':
        failed.append(lang)
payload = {
    'schemaVersion': 1,
    'mode': mode,
    'generatedAt': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
    'languages': languages,
    'failed': failed,
}
path = root / 'artifacts' / 'verification.json'
path.write_text(json.dumps(payload, indent=2) + chr(10), encoding='utf-8')
print('wrote', path)
" "${ROOT}" "${MODE}" "${payload_langs[@]}"

if ((${#failed[@]} > 0)); then
  echo "FAILED languages: ${failed[*]}"
  exit 1
fi

echo "All requested language templates passed."
