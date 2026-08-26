#!/usr/bin/env bash
# Run the verify.sh suite for every language template via docker compose.
#
# Usage:
#   scripts/verify-all.sh [language...]   # default: all eight languages
#
# Each language's phases run inside its hermetic container (docker-compose.yml).
set -euo pipefail

readonly ALL_LANGS=(python typescript go rust java csharp kotlin swift)

if [ "$#" -gt 0 ]; then
  langs=("$@")
else
  langs=("${ALL_LANGS[@]}")
fi

declare -A result=()
failed=()

for lang in "${langs[@]}"; do
  echo ""
  echo "== verify-all: ${lang} =="
  if docker compose run --rm "${lang}"; then
    result["${lang}"]=OK
  else
    result["${lang}"]=FAIL
    failed+=("${lang}")
  fi
done

echo ""
echo "Summary"
echo "------------------------------"
printf '%-12s %s\n' 'LANGUAGE' 'RESULT'
echo "------------------------------"
for lang in "${langs[@]}"; do
  printf '%-12s %s\n' "${lang}" "${result[${lang}]}"
done
echo "------------------------------"

if [ "${#failed[@]}" -gt 0 ]; then
  echo "FAILED languages: ${failed[*]}"
  exit 1
fi

echo "All requested language templates passed."
