#!/usr/bin/env bash
# Negative fixtures: every gate must demonstrably bite (CONTRACTS.md §3).
#
# Manifest (fixture -> gate -> expected stable signal):
# +-----------------+----------+------------------------------------------------------+
# | fixture         | gate     | expected signal                                      |
# +-----------------+----------+------------------------------------------------------+
# | too_complex     | lint     | ruleId "complexity" in eslint JSON output            |
# | type_violation  | types    | diagnostic "error TS2322" from tsc                   |
# | arch_violation  | arch     | rule name "domain-no-outbound" (depcruise)           |
# | dead_code       | deadcode | unused file "_tmp_dead_code_fixture.ts" (knip)       |
# | insecure        | lint     | message "forbidden: eval()"                          |
# | printing        | lint     | ruleId "no-console"                                  |
# | naive_datetime  | lint     | message "forbidden: new Date()"                      |
# | todo_comment    | lint     | ruleId "no-warning-comments"                         |
# | unformatted     | format   | "Code style issues found" (prettier --check)         |
# +-----------------+----------+------------------------------------------------------+
#
# ESLint's human formats print rule names, not always stable identifiers, so
# the lint fixtures are asserted against --format json where every finding
# carries its machine-readable ruleId and message.
#
# Fixture files are excluded from the main tooling globs by native scoping
# (the eslint global ignore list, .prettierignore, tsconfig include/exclude)
# — never inline suppressions. Explicit paths are re-admitted for probing
# via `eslint --no-ignore` and `prettier --ignore-path /dev/null`. The arch
# fixture is copied into src/domain/ for one depcruise run (the layer rules
# anchor at ^src/) and the dead-code fixture into src/ for one knip run
# (knip analyzes entry-reachable project files only; it reports the copy as
# an unused file — file-level death — rather than an unused export); a trap
# removes both copies.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

corepack enable pnpm >/dev/null 2>&1 || true

readonly ARCH_TMP="src/domain/_tmp_arch_violation_fixture.ts"
readonly DEADCODE_TMP="src/_tmp_dead_code_fixture.ts"

declare -a FAILURES=()

cleanup() {
  rm -f "${ARCH_TMP}" "${DEADCODE_TMP}"
}
trap cleanup EXIT INT TERM

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

cp bad_examples/arch_violation/arch_violation.ts "${ARCH_TMP}"
cp bad_examples/dead_code/dead_code.ts "${DEADCODE_TMP}"

expect_failure too_complex '"ruleId"\s*:\s*"complexity"' \
  pnpm exec eslint --no-ignore --format json bad_examples/too_complex/too_complex.ts
expect_failure type_violation 'error TS2322' \
  pnpm exec tsc --noEmit -p bad_examples/type_violation
expect_failure arch_violation 'domain-no-outbound' \
  pnpm exec depcruise src
expect_failure dead_code '_tmp_dead_code_fixture' \
  pnpm exec knip
expect_failure insecure 'forbidden: eval' \
  pnpm exec eslint --no-ignore --format json bad_examples/insecure/insecure.ts
expect_failure printing '"ruleId"\s*:\s*"no-console"' \
  pnpm exec eslint --no-ignore --format json bad_examples/printing/printing.ts
expect_failure naive_datetime 'forbidden: new Date' \
  pnpm exec eslint --no-ignore --format json bad_examples/naive_datetime/naive_datetime.ts
expect_failure todo_comment '"ruleId"\s*:\s*"no-warning-comments"' \
  pnpm exec eslint --no-ignore --format json bad_examples/todo_comment/todo_comment.ts
# --ignore-path /dev/null empties the ignore list so the explicitly named
# fixture is checked despite .prettierignore excluding bad_examples/.
expect_failure unformatted 'Code style issues found' \
  pnpm exec prettier --check --ignore-path /dev/null bad_examples/unformatted/unformatted.ts

if ((${#FAILURES[@]} > 0)); then
  printf 'FAILED fixtures:\n'
  printf '  - %s\n' "${FAILURES[@]}"
  exit 1
fi
printf 'All negative fixtures caught.\n'
