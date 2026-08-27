#!/usr/bin/env bash
# Negative fixtures: every gated detector must demonstrably bite (CONTRACTS.md §4).
#
# Manifest (fixture -> gate -> expected stable signal):
# +---------------+----------+-----------------------------------------------+
# | fixture       | gate     | expected signal                               |
# +---------------+----------+-----------------------------------------------+
# | unformatted   | format   | whitespace / would be formatted from format   |
# | compile_fail  | compile  | C# compiler error CS0029 (type mismatch)      |
# +---------------+----------+-----------------------------------------------+
#
# Fixtures live outside Warehouse.sln so the main format/compile gates never
# see them. assert.sh invokes the tools scoped to each fixture project.

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
    tail -n 40 "${output}" >&2 || true
  else
    printf 'FIXTURE %s: CAUGHT (%s)\n' "${name}" "${signal}"
  fi
  rm -f "${output}"
}

expect_failure unformatted 'error WHITESPACE' \
  dotnet format bad_examples/unformatted/Unformatted.csproj --verify-no-changes --verbosity diagnostic

expect_failure compile_fail 'CS0029' \
  dotnet build bad_examples/compile_fail/CompileFail.csproj --nologo

if ((${#FAILURES[@]} > 0)); then
  printf 'FAILED fixtures:\n'
  printf '  - %s\n' "${FAILURES[@]}"
  exit 1
fi
printf 'All negative fixtures caught.\n'
