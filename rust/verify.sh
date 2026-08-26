#!/usr/bin/env bash
# Canonical gate runner for the Rust template (CONTRACTS.md §1).
#
# Usage:
#   ./verify.sh              # all phases, canonical order
#   ./verify.sh [phase...]   # subset, still canonical order
#
# Prints exactly one "GATE <phase>: PASS" line per phase on stdout; tool
# diagnostics go to stderr. Exits nonzero at the first failing phase.
# The optional `mutation` phase runs only with VERIFY_TIER=full (nightly).

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

# Container preamble (CONTRACTS.md §4): trust the mounted workspace.
git config --global --add safe.directory "${GITHUB_WORKSPACE:-/workspace}" >/dev/null 2>&1 || true

# Pinned tool versions: installed fresh by the deps phase, never baked into
# the image (CONTRACTS.md §6). All four install through `cargo install
# --locked <crate>@<pin>`, so every binary is checksum-verified through the
# crates.io index; the exact pins are the supply-chain contract
# (LANG_SPEC.md). Bump them together after checking clippy/nextest compat.
readonly NEXTEST_VERSION="0.9.143"
readonly LLVM_COV_VERSION="0.9.0"
readonly CARGO_DENY_VERSION="0.20.2"
readonly CARGO_SHEAR_VERSION="1.13.4"
readonly CARGO_MUTANTS_VERSION="27.1.0" # installed lazily by run_mutation

# R3 floor rule: floor = measured line coverage - 4, rounded down, min 80.
# Baseline measured on the first green run: 95.77% of lines across the whole
# workspace (615 instrumented, 26 missed; see LANG_SPEC.md Thresholds). The
# floor is a committed constant, like the tool pins above — change it in
# review, not per-run.
readonly COVERAGE_FLOOR=91

# Hermetic caches + tool binaries live in gitignored workspace directories
# (CONTRACTS.md §4); nothing leaks outside /workspace or into image layers.
export CARGO_HOME="$PWD/.cargo-home"
export CARGO_TARGET_DIR="$PWD/target"
export CARGO_INCREMENTAL=0
mkdir -p .cargo-home .cache
export PATH="${CARGO_HOME}/bin:${PATH}"

readonly ALL_PHASES=(
  deps format lint types arch test coverage deadcode security deps-hygiene negative
)

usage() {
  printf 'usage: %s [phase...]\nphases: %s mutation\n' \
    "${0##*/}" "$(IFS=' '; echo "${ALL_PHASES[*]}")" >&2
}

select_phases() {
  local requested
  if (($# == 0)); then
    printf '%s\n' "${ALL_PHASES[@]}"
    return 0
  fi
  local phases=()
  for requested in "$@"; do
    case "${requested}" in
      deps | format | lint | types | arch | test | coverage | deadcode | security | deps-hygiene | negative | mutation)
        phases+=("${requested}")
        ;;
      *)
        printf 'unknown phase: %s\n' "${requested}" >&2
        usage
        return 64
        ;;
    esac
  done
  # Reorder the requested subset into canonical order.
  local ordered=()
  for requested in "${ALL_PHASES[@]}" mutation; do
    local candidate
    for candidate in "${phases[@]}"; do
      if [[ "${candidate}" == "${requested}" ]]; then
        ordered+=("${candidate}")
      fi
    done
  done
  printf '%s\n' "${ordered[@]}"
}

gate() {
  local phase="$1"
  shift
  local log rc
  log="$(mktemp)"
  rc=0
  "$@" >"${log}" 2>&1 || rc=$?
  if ((rc == 0)); then
    cat "${log}" >&2
    rm -f "${log}"
    printf 'GATE %s: PASS\n' "${phase}"
  else
    tail -n 25 "${log}" >&2 || true
    rm -f "${log}"
    printf 'GATE %s: FAIL (exit %s)\n' "${phase}" "${rc}"
    exit "${rc}"
  fi
}

install_tool() {
  local crate="$1" version="$2"
  if ! cargo install --locked "${crate}@${version}"; then
    printf '%s %s install failed\n' "${crate}" "${version}" >&2
    return 1
  fi
}

run_deps() {
  # Errexit is suspended inside gate()'s `|| rc=$?` capture, so EVERY
  # fallible step here fails explicitly instead of half-installing tools
  # and letting a later phase fail with a confusing missing-command error.
  if ! cargo fetch --locked; then
    printf 'cargo fetch --locked failed (stale Cargo.lock or unreachable registry)\n' >&2
    return 1
  fi
  # Components live in the container's ephemeral RUSTUP_HOME and the
  # official image ships a minimal toolchain, so add what the gates need on
  # every cold run: rustfmt + clippy for format/lint, llvm-tools-preview
  # because cargo-llvm-cov drives its llvm-cov/llvm-profdata.
  if ! rustup component add rustfmt clippy llvm-tools-preview; then
    printf 'rustup component install failed\n' >&2
    return 1
  fi
  install_tool cargo-nextest "${NEXTEST_VERSION}" || return 1
  install_tool cargo-llvm-cov "${LLVM_COV_VERSION}" || return 1
  install_tool cargo-deny "${CARGO_DENY_VERSION}" || return 1
  install_tool cargo-shear "${CARGO_SHEAR_VERSION}" || return 1
}

run_lint() {
  # Warnings are errors twice over: `-D warnings` denies at the rustc layer,
  # and CARGO_BUILD_WARNINGS=deny (stable since Cargo 1.97) denies at the
  # cargo layer WITHOUT invalidating build caches the way
  # RUSTFLAGS="-D warnings" would — that is why it is preferred on the
  # pinned 1.98 toolchain. Complexity ceilings live in [workspace.lints]
  # (too_many_lines deny) with their thresholds in clippy.toml.
  CARGO_BUILD_WARNINGS=deny cargo clippy --all-targets --locked -- -D warnings
}

run_arch() {
  assert_no_edge warehouse-domain 'warehouse-(application|adapters)'
  assert_no_edge warehouse-application 'warehouse-adapters'
}

assert_no_edge() {
  local crate="$1" forbidden_regex="$2" tree hits
  # Rust ships no ArchUnit equivalent; `cargo tree` IS the dependency
  # oracle. Dev-dependencies are excluded (-e normal) because the
  # integration tests deliberately wire adapters into the use case; the
  # production graph must stay strictly inward-pointing. Dependency cycles
  # are banned by cargo itself during resolution — a cycle would fail this
  # query before any assertion runs.
  if ! tree="$(cargo tree -p "${crate}" -e normal --prefix none)"; then
    printf 'cargo tree failed for %s\n' "${crate}" >&2
    return 1
  fi
  hits="$(printf '%s\n' "${tree}" | grep -E "${forbidden_regex}" || true)"
  if [[ -n "${hits}" ]]; then
    printf 'layering violation: `%s` depends on:\n%s\n' "${crate}" "${hits}" >&2
    return 1
  fi
}

run_types() {
  # Redundant-ish with clippy by design: keeps the canonical phase slot for
  # "the compiler accepts this" independent of any linter's opinion, so a
  # clippy regression can never masquerade as a type error (and vice versa).
  cargo check --all-targets --locked
}

run_coverage() {
  # Fused with nextest so coverage runs the SAME runner as the test gate;
  # --fail-under-lines is llvm-cov's native floor flag. Floor rationale in
  # COVERAGE_FLOOR above and LANG_SPEC.md Thresholds.
  cargo llvm-cov nextest --locked --fail-under-lines "${COVERAGE_FLOOR}"
}

run_deps_hygiene() {
  # Freshness: resolution with --locked succeeds ONLY when Cargo.lock is
  # exactly what the manifests demand — cargo's equivalent of python's
  # `uv lock --check`. Vulnerability auditing lives in security
  # (cargo-deny advisories), matching CONTRACTS §1's split of concerns.
  cargo metadata --locked --format-version 1 >/dev/null
}

run_mutation() {
  if [[ "${VERIFY_TIER:-}" == "full" ]]; then
    # Nightly tier: install the pinned mutator lazily (default tier never
    # pays its compile cost) and require a kill-score floor. The score line
    # ("killed X of Y") is parsed from the summary; an unparseable summary
    # FAILS the gate rather than silently passing.
    install_tool cargo-mutants "${CARGO_MUTANTS_VERSION}" || return 1
    local floor="${MUTATION_FLOOR:-70}"
    local log rc killed total score
    log="$(mktemp)"
    rc=0
    cargo mutants --workspace >"${log}" 2>&1 || rc=$?
    if ((rc != 0)); then
      tail -n 25 "${log}" >&2
      printf 'GATE mutation: FAIL (cargo-mutants exited %s)\n' "${rc}"
      exit "${rc}"
    fi
    killed="$(grep -oE '[0-9]+ killed' "${log}" | grep -oE '[0-9]+' | head -n 1 || true)"
    total="$(grep -oE '[0-9]+ mutants' "${log}" | grep -oE '[0-9]+' | head -n 1 || true)"
    if [[ -z "${killed}" || -z "${total}" || "${total}" -eq 0 ]]; then
      tail -n 25 "${log}" >&2
      printf 'GATE mutation: FAIL (no parsable cargo-mutants summary)\n'
      exit 1
    fi
    score=$((100 * killed / total))
    rm -f "${log}"
    if ((score >= floor)); then
      printf 'GATE mutation: PASS (score %d >= floor %d)\n' "${score}" "${floor}"
    else
      printf 'GATE mutation: FAIL (score %d < floor %d)\n' "${score}" "${floor}"
      exit 1
    fi
  else
    printf 'GATE mutation: SKIP (nightly tier only)\n'
  fi
}

phase_list="$(select_phases "$@")" || exit $?
mapfile -t phases <<<"${phase_list}"

for phase in "${phases[@]}"; do
  case "${phase}" in
    deps) gate deps run_deps ;;
    format) gate format cargo fmt --all --check ;;
    lint) gate lint run_lint ;;
    types) gate types run_types ;;
    arch) gate arch run_arch ;;
    test) gate test cargo nextest run --locked ;;
    coverage) gate coverage run_coverage ;;
    deadcode) gate deadcode cargo shear ;;
    security) gate security cargo deny check advisories bans licenses sources ;;
    deps-hygiene) gate deps-hygiene run_deps_hygiene ;;
    negative) gate negative bash bad_examples/assert.sh ;;
    mutation) run_mutation ;;
  esac
done
