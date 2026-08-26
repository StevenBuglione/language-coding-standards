#!/usr/bin/env bash
# Negative fixtures: every gate must demonstrably bite (CONTRACTS.md §3).
#
# Manifest (fixture -> gate -> expected stable signal):
# +------------------+----------+---------------------------------------------------+
# | fixture          | gate     | expected signal                                   |
# +------------------+----------+---------------------------------------------------+
# | too_complex      | lint     | clippy::too_many_lines in JSON diagnostics        |
# | unwrap_used      | lint     | clippy::unwrap_used in JSON diagnostics           |
# | indexing_slicing | lint     | clippy::indexing_slicing in JSON diagnostics      |
# | print_stdout     | lint     | clippy::print_stdout in JSON diagnostics          |
# | todo_macro       | lint     | clippy::todo in JSON diagnostics                  |
# | dead_code        | deadcode | "never used" under -D warnings                    |
# | pub_api_leak     | arch     | "unreachable" (unreachable_pub under -D warnings) |
# | unsafe_block     | types    | unsafe_code forbid compile error                  |
# | unformatted      | format   | rustfmt prints a diff ("Diff in")                 |
# +------------------+----------+---------------------------------------------------+
#
# Human-format rustc/clippy output renders lint names inconsistently across
# versions, so the clippy probes assert against --message-format json, where
# every finding carries its machine-readable code.code field — the same
# discipline python's assert.sh applies to ruff.
#
# Each fixture is its own standalone workspace ([workspace] table in its
# manifest) and is additionally excluded from the template workspace root,
# so it is invisible to every main-gate glob BY CONSTRUCTION. The probes
# pass explicit --manifest-path values plus the exact lint flags production
# code inherits from [workspace.lints], keeping fixture files free of any
# suppression hacks.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

declare -a FAILURES=()

export CARGO_HOME="$PWD/.cargo-home"
export CARGO_TARGET_DIR="$PWD/bad_examples/.target"
mkdir -p "${CARGO_TARGET_DIR}"
export PATH="${CARGO_HOME}/bin:${PATH}"

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

clippy_probe() {
  local manifest="$1"
  shift
  cargo clippy --manifest-path "${manifest}" --offline --message-format=json -- "$@"
}

expect_failure too_complex 'clippy::too_many_lines' \
  clippy_probe bad_examples/too_complex/Cargo.toml -D warnings -D clippy::too_many_lines

expect_failure unwrap_used 'clippy::unwrap_used' \
  clippy_probe bad_examples/unwrap_used/Cargo.toml -D warnings -D clippy::unwrap_used

expect_failure indexing_slicing 'clippy::indexing_slicing' \
  clippy_probe bad_examples/indexing_slicing/Cargo.toml -D warnings -D clippy::indexing_slicing

expect_failure print_stdout 'clippy::print_stdout' \
  clippy_probe bad_examples/print_stdout/Cargo.toml -D warnings -D clippy::print_stdout

expect_failure todo_macro 'clippy::todo' \
  clippy_probe bad_examples/todo_macro/Cargo.toml -D warnings -D clippy::todo

expect_failure dead_code 'never used' \
  env RUSTFLAGS=-Dwarnings cargo check --manifest-path bad_examples/dead_code/Cargo.toml --offline

expect_failure pub_api_leak 'unreachable' \
  cargo rustc --manifest-path bad_examples/pub_api_leak/Cargo.toml --offline -- -D warnings -W unreachable_pub

expect_failure unsafe_block 'unsafe.code|E0133' \
  cargo check --manifest-path bad_examples/unsafe_block/Cargo.toml --offline

expect_failure unformatted 'Diff in' \
  cargo fmt --check --manifest-path bad_examples/unformatted/Cargo.toml

if ((${#FAILURES[@]} > 0)); then
  printf 'FAILED fixtures:\n'
  printf '  - %s\n' "${FAILURES[@]}"
  exit 1
fi
printf 'All negative fixtures caught.\n'
