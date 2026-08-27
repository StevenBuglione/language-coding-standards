#!/usr/bin/env bash
# Negative fixtures: every implemented gate must demonstrably bite (CONTRACTS.md §4).
#
# Manifest (fixture -> gate -> expected stable signal):
# +------------------+--------+------------------------------------------+
# | fixture          | gate   | expected signal                          |
# +------------------+--------+------------------------------------------+
# | Unformatted      | format | ktlint rule id "standard:indent"         |
# | WildcardImport   | lint   | ktlint rule id "no-wildcard-imports"     |
# +------------------+--------+------------------------------------------+
#
# Fixtures live outside production source sets so ktlintCheck on the main
# tree never sees them. This script re-invokes ktlint scoped to each file.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

export GRADLE_USER_HOME="${PWD}/.gradle-home"
mkdir -p "${GRADLE_USER_HOME}"

gradle_bin() {
  if [[ -x ./gradlew ]]; then
    ./gradlew --no-daemon --console=plain "$@"
  else
    gradle --no-daemon --console=plain "$@"
  fi
}

declare -a FAILURES=()

expect_failure() {
  local name="$1" signal="$2"
  shift 2
  local output rc
  output="$(mktemp)"
  rc=0
  "$@" >"${output}" 2>&1 || rc=$?
  if ((rc == 0)); then
    FAILURES+=("${name}: exited 0, expected nonzero")
    printf 'FIXTURE %s: MISSED (exit 0)\n' "${name}"
  elif ! grep -qE -- "${signal}" "${output}"; then
    FAILURES+=("${name}: signal '${signal}' absent from output")
    printf 'FIXTURE %s: MISSED (no %s)\n' "${name}" "${signal}"
    tail -n 40 "${output}" >&2 || true
  else
    printf 'FIXTURE %s: CAUGHT (%s)\n' "${name}" "${signal}"
  fi
  rm -f "${output}"
}

expect_failure unformatted 'standard:indent' \
  gradle_bin ktlintFixture -Pfixture=bad_examples/unformatted/Unformatted.kt
expect_failure wildcard_imports 'no-wildcard-imports' \
  gradle_bin ktlintFixture -Pfixture=bad_examples/lint/WildcardImport.kt

if ((${#FAILURES[@]} > 0)); then
  printf 'FAILED fixtures:\n'
  printf '  - %s\n' "${FAILURES[@]}"
  exit 1
fi
printf 'All negative fixtures caught.\n'
