#!/usr/bin/env bash
# Negative fixtures: every wired gate must demonstrably bite (CONTRACTS.md §4).
#
# Manifest (fixture -> gate -> expected stable signal):
# +-----------------+---------+--------------------------------------------+
# | fixture         | gate    | expected signal                            |
# +-----------------+---------+--------------------------------------------+
# | unformatted     | format  | swift format lint reports the file         |
# | type_violation  | compile | cannot convert value of type 'String'      |
# +-----------------+---------+--------------------------------------------+
#
# Fixtures live outside Sources/ and Tests/, so the main package never sees
# them. type_violation is a nested SwiftPM package compiled in isolation.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

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
  else
    printf 'FIXTURE %s: CAUGHT (%s)\n' "${name}" "${signal}"
  fi
  rm -f "${output}"
}

expect_failure type_violation "cannot convert value of type 'String'" \
  swift build --package-path bad_examples/type_violation

if swift format --help >/dev/null 2>&1; then
  expect_failure unformatted 'Unformatted.swift' \
    swift format lint --strict bad_examples/unformatted/Unformatted.swift
else
  printf 'FIXTURE unformatted: SKIP (swift format not available)\n'
fi

if ((${#FAILURES[@]} > 0)); then
  printf 'FAILED fixtures:\n'
  printf '  - %s\n' "${FAILURES[@]}"
  exit 1
fi
printf 'All negative fixtures caught.\n'
