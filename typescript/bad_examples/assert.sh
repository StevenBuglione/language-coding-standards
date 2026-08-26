#!/usr/bin/env bash
# Negative fixtures: every gate must demonstrably bite (CONTRACTS.md §3).
#
# Manifest (fixture -> gate -> expected stable signal):
# +------------------+----------+------------------------------------------------------+
# | fixture          | gate     | expected signal                                      |
# +------------------+----------+------------------------------------------------------+
# | too_complex      | lint     | ruleId "complexity" in eslint JSON output            |
# | type_violation   | types    | diagnostic "error TS2322" from tsc                   |
# | arch_violation   | arch     | rule name "domain-no-outbound" (depcruise)           |
# | dead_code        | deadcode | unused file "_tmp_dead_code_fixture.ts" (knip)       |
# | dead_code_export | deadcode | unused export "_tmpDeadExportProbe" (knip)           |
# | insecure         | lint     | message "forbidden: eval()"                          |
# | printing         | lint     | ruleId "no-console"                                  |
# | naive_datetime   | lint     | message "forbidden: new Date()"                      |
# | todo_comment     | lint     | ruleId "no-warning-comments"                         |
# | unformatted      | format   | "Code style issues found" (prettier --check)         |
# +------------------+----------+------------------------------------------------------+
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
# anchor at ^src/). Dead code is proven on both knip layers: the fixture
# copy surfaces as an unused FILE, and a dead export appended to a reachable
# module (src/domain/sku.ts, backed up first) surfaces as an unused EXPORT.
# That export-level probe only holds while src/index.ts forwards symbols by
# explicit name — an `export *` barrel at the entry would exempt every
# transitively forwarded symbol from knip's analysis. A trap restores
# everything.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

corepack enable pnpm >/dev/null 2>&1 || true

readonly ARCH_TMP="src/domain/_tmp_arch_violation_fixture.ts"
readonly DEADCODE_TMP="src/_tmp_dead_code_fixture.ts"
SKU_BACKUP="$(mktemp)"

declare -a FAILURES=()

cleanup() {
  rm -f "${ARCH_TMP}" "${DEADCODE_TMP}"
  # Restore the pristine sku.ts even after a partial append, then drop the
  # backup — the tree must look untouched whether the probes pass or die.
  if [[ -f "${SKU_BACKUP}" ]]; then
    cp "${SKU_BACKUP}" src/domain/sku.ts
  fi
  rm -f "${SKU_BACKUP}"
}
trap cleanup EXIT
# Interrupts must not masquerade as success: cleanup first, then re-raise a
# non-zero exit (130 SIGINT / 143 SIGTERM).
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

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
# Export-level dead-code probe: append an unreferenced export to a reachable
# module so knip must flag it as an unused EXPORT (not just an unused file).
# The original is backed up and restored by the trap.
cp src/domain/sku.ts "${SKU_BACKUP}"
cat >>src/domain/sku.ts <<'EOF'

export function _tmpDeadExportProbe(): number {
  return 0;
}
EOF

expect_failure too_complex '"ruleId"\s*:\s*"complexity"' \
  pnpm exec eslint --no-ignore --format json bad_examples/too_complex/too_complex.ts
expect_failure type_violation 'error TS2322' \
  pnpm exec tsc --noEmit -p bad_examples/type_violation
expect_failure arch_violation 'domain-no-outbound' \
  pnpm exec depcruise src
expect_failure dead_code '_tmp_dead_code_fixture' \
  pnpm exec knip
expect_failure dead_code_export '_tmpDeadExportProbe' \
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
