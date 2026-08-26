#!/usr/bin/env bash
# Negative fixtures: every gate must demonstrably bite (CONTRACTS.md §3).
#
# Manifest (fixture -> gate -> expected stable signal):
# +-----------------+-----------+--------------------------------------------+
# | fixture         | gate      | expected signal                            |
# +-----------------+-----------+--------------------------------------------+
# | too_complex     | lint      | rule code PLR0912 in ruff JSON output      |
# | type_violation  | types     | diagnostic name reportArgumentType         |
# | arch_violation  | arch      | lint-imports prints "Broken contracts"     |
# | dead_code       | deadcode  | unused function 'orphaned_helper'          |
# | insecure        | lint      | rule code S105 in ruff JSON output         |
# | printing        | lint      | rule code T201 in ruff JSON output         |
# | naive_datetime  | lint      | rule code DTZ005 in ruff JSON output       |
# | todo_comment    | lint      | rule code TD003 in ruff JSON output        |
# | unformatted     | format    | "would be reformatted"                     |
# +-----------------+-----------+--------------------------------------------+
#
# Ruff's human formats print rule names, not stable codes, so the lint
# fixtures are asserted against --output-format json where every finding
# carries its machine-readable code.
#
# Fixture files are passed to the tools as explicit paths; explicit paths are
# checked even when excluded from discovery (ruff has no force-exclude here,
# and basedpyright honors include-scoping only for its default run). The arch
# fixture is copied into the package tree for one import-linter run because
# import-linter analyzes installed modules only; a trap removes the copy.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

readonly ARCH_TMP="src/warehouse/domain/_tmp_arch_violation_fixture.py"

declare -a FAILURES=()

cleanup() {
  rm -f "${ARCH_TMP}"
}
trap cleanup EXIT

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

cp bad_examples/arch_violation/arch_violation.py "${ARCH_TMP}"

expect_failure too_complex '"code": "PLR0912"' \
  uv run ruff check bad_examples/too_complex/too_complex.py --output-format json
expect_failure type_violation 'reportArgumentType' \
  uv run basedpyright bad_examples/type_violation/type_violation.py
expect_failure arch_violation 'Broken contracts' \
  uv run lint-imports
expect_failure dead_code "unused function 'orphaned_helper'" \
  uv run vulture bad_examples/dead_code/dead_code.py --min-confidence 60
expect_failure insecure '"code": "S105"' \
  uv run ruff check bad_examples/insecure/insecure.py --output-format json
expect_failure printing '"code": "T201"' \
  uv run ruff check bad_examples/printing/printing.py --output-format json
expect_failure naive_datetime '"code": "DTZ005"' \
  uv run ruff check bad_examples/naive_datetime/naive_datetime.py --output-format json
expect_failure todo_comment '"code": "TD003"' \
  uv run ruff check bad_examples/todo_comment/todo_comment.py --output-format json
expect_failure unformatted 'would be reformatted' \
  uv run ruff format --check bad_examples/unformatted/unformatted.py

if ((${#FAILURES[@]} > 0)); then
  printf 'FAILED fixtures:\n'
  printf '  - %s\n' "${FAILURES[@]}"
  exit 1
fi
printf 'All negative fixtures caught.\n'
