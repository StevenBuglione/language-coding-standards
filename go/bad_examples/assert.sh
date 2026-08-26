#!/usr/bin/env bash
# Negative fixtures: every gate must demonstrably bite (CONTRACTS.md §3).
#
# Manifest (fixture -> gate -> expected stable signal):
# +----------------+----------+-------------------------------------------------+
# | fixture        | gate     | expected signal                                 |
# +----------------+----------+-------------------------------------------------+
# | too_complex    | lint     | finding from linter cyclop                      |
# | type_violation | types    | compile error 'cannot use' from go build        |
# | arch_violation | arch     | finding from linter depguard                    |
# | dead_code      | lint     | 'is unused' finding from the unused linter      |
# | insecure       | lint     | gosec rule G101 in output                       |
# | printing       | lint     | forbidigo finding on fmt.Print*                 |
# | naive_datetime | lint     | forbidigo finding on time.Now                   |
# | todo_comment   | lint     | grep step reports a TODO marker                 |
# | unformatted    | format   | unified diff lines (gofumpt/gci would rewrite)  |
# +----------------+----------+-------------------------------------------------+
#
# bad_examples/ is its OWN Go module, so the parent module's ./... never
# reaches it by construction. The lint/format probes therefore run INSIDE
# this module with an explicit -c ../.golangci.yaml; text colors are off in
# the config so "(lintername)" suffixes stay grep-stable.
#
# The arch fixture cannot prove anything from inside its own module: it
# imports warehouse/internal/adapters, which Go's internal-package rule
# already rejects for a foreign module. Like python's import-linter probe,
# assert.sh copies it into internal/domain/ for one depguard-only run and
# removes it again in a trap.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

readonly ARCH_TMP="internal/domain/zz_arch_violation_fixture.go"

declare -a FAILURES=()

cleanup() {
  rm -f "${ARCH_TMP}"
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

# Inverted probe for the TODO/FIXME ban: the gate IS a grep, so a caught
# fixture means the grep found the marker (exit 0) and reported it.
expect_grep_hit() {
  local name="$1" signal="$2"
  shift 2
  local output rc
  output="$(mktemp)"
  rc=0
  "$@" >"${output}" 2>&1 || rc=$?
  if ((rc != 0)); then
    FAILURES+=("${name}: grep exited ${rc}, expected to find the marker")
    printf 'FIXTURE %s: MISSED (grep exit %s)\n' "${name}" "${rc}"
  elif ! grep -qE -- "${signal}" "${output}"; then
    FAILURES+=("${name}: signal '${signal}' absent from output")
    printf 'FIXTURE %s: MISSED (no %s)\n' "${name}" "${signal}"
  else
    printf 'FIXTURE %s: CAUGHT (%s)\n' "${name}" "${signal}"
  fi
  rm -f "${output}"
}

# Run golangci-lint against one fixture package, scoped to THIS module.
fixture_lint() {
  local dir="$1"
  shift
  (
    cd bad_examples
    golangci-lint run -c ../.golangci.yaml "./${dir}/..." "$@"
  )
}

cp bad_examples/arch_violation/arch_violation.go "${ARCH_TMP}"

expect_failure too_complex 'cyclop' \
  fixture_lint too_complex
expect_failure type_violation 'cannot use' \
  bash -c 'cd bad_examples && go build ./type_violation/...'
expect_failure arch_violation 'depguard' \
  golangci-lint run --default=none -E depguard ./internal/domain/...
expect_failure dead_code 'is unused' \
  fixture_lint dead_code
expect_failure insecure 'G101' \
  fixture_lint insecure
expect_failure printing 'forbidigo' \
  fixture_lint printing
expect_failure naive_datetime 'forbidigo' \
  fixture_lint naive_datetime
expect_grep_hit todo_comment 'TODO' \
  grep -nE '(TODO|FIXME)' bad_examples/todo_comment/todo_comment.go
expect_failure unformatted '^(\+|-)' \
  bash -c 'cd bad_examples && golangci-lint fmt --diff -c ../.golangci.yaml ./unformatted/...'

if ((${#FAILURES[@]} > 0)); then
  printf 'FAILED fixtures:\n'
  printf '  - %s\n' "${FAILURES[@]}"
  exit 1
fi
printf 'All negative fixtures caught.\n'
