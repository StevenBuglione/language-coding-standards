#!/usr/bin/env bash
# Canonical gate runner for the Rust template (CONTRACTS.md §1).

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=capabilities.sh
source ./capabilities.sh

git config --global --add safe.directory "${GITHUB_WORKSPACE:-/workspace}" >/dev/null 2>&1 || true

readonly NEXTEST_VERSION="0.9.143"
readonly LLVM_COV_VERSION="0.9.0"
readonly CARGO_DENY_VERSION="0.20.2"
readonly CARGO_SHEAR_VERSION="1.13.4"
readonly CARGO_MUTANTS_VERSION="27.1.0"
readonly COVERAGE_FLOOR=91

export CARGO_HOME="$PWD/.cargo-home"
export CARGO_TARGET_DIR="$PWD/target"
export CARGO_INCREMENTAL=0
mkdir -p .cargo-home .cache
export PATH="${CARGO_HOME}/bin:${PATH}"

usage() {
  printf 'usage: %s [capability...]\n' "${0##*/}" >&2
  printf 'capabilities: %s\n' "${CANONICAL_CAPABILITIES[*]}" >&2
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
  cargo fetch --locked || return 1
  rustup component add rustfmt clippy llvm-tools-preview || return 1
  install_tool cargo-nextest "${NEXTEST_VERSION}" || return 1
  install_tool cargo-llvm-cov "${LLVM_COV_VERSION}" || return 1
  install_tool cargo-deny "${CARGO_DENY_VERSION}" || return 1
  install_tool cargo-shear "${CARGO_SHEAR_VERSION}"
}

run_lint() {
  CARGO_BUILD_WARNINGS=deny cargo clippy --all-targets --locked -- -D warnings
}

assert_no_edge() {
  local crate="$1" forbidden_regex="$2" tree hits
  tree="$(cargo tree -p "${crate}" -e normal --prefix none)" || return 1
  hits="$(printf '%s\n' "${tree}" | grep -E "${forbidden_regex}" || true)"
  if [[ -n "${hits}" ]]; then
    printf 'layering violation: `%s` depends on:\n%s\n' "${crate}" "${hits}" >&2
    return 1
  fi
}

run_arch() {
  assert_no_edge warehouse-domain 'warehouse-(application|adapters)' || return 1
  assert_no_edge warehouse-application 'warehouse-adapters'
}

run_coverage() {
  cargo llvm-cov nextest --locked --no-tests=fail --fail-under-lines "${COVERAGE_FLOOR}"
}

run_deps_hygiene() {
  cargo metadata --locked --format-version 1 >/dev/null
}

run_mutation() {
  if [[ "${VERIFY_TIER:-}" != "full" ]]; then
    printf 'GATE mutation: SKIP_UNSUPPORTED(full tier only)\n'
    return 0
  fi
  install_tool cargo-mutants "${CARGO_MUTANTS_VERSION}" || return 1
  local floor=70 log rc killed total score
  log="$(mktemp)"
  rc=0
  cargo mutants --workspace >"${log}" 2>&1 || rc=$?
  if ((rc != 0)); then
    tail -n 25 "${log}" >&2
    rm -f "${log}"
    printf 'GATE mutation: FAIL (cargo-mutants exited %s)\n' "${rc}"
    exit "${rc}"
  fi
  killed="$(grep -oE '[0-9]+ killed' "${log}" | grep -oE '[0-9]+' | head -n 1 || true)"
  total="$(grep -oE '[0-9]+ mutants' "${log}" | grep -oE '[0-9]+' | head -n 1 || true)"
  if [[ -z "${killed}" || -z "${total}" || "${total}" -eq 0 ]]; then
    tail -n 25 "${log}" >&2
    rm -f "${log}"
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
}

run_package() {
  # Without --no-verify, Cargo extracts the crate and builds it from the
  # packaged contents, catching missing files and invalid package metadata.
  cargo package -p warehouse-domain --locked --allow-dirty
}

cap_list="$(expand_capabilities "$@")" || { usage; exit 64; }
mapfile -t phases <<<"${cap_list}"

for phase in "${phases[@]}"; do
  case "${phase}" in
    bootstrap) gate bootstrap run_deps ;;
    format) gate format cargo fmt --all --check ;;
    lint) gate lint run_lint ;;
    compile) gate compile cargo check --all-targets --locked ;;
    architecture) gate architecture run_arch ;;
    unit) gate unit cargo nextest run --locked --no-tests=fail --lib --bins ;;
    property)
      gate property cargo nextest run --locked --no-tests=fail \
        -p warehouse-domain --test money_properties --test order_properties
      ;;
    integration) gate integration cargo nextest run --locked --no-tests=fail --test place_order ;;
    package) gate package run_package ;;
    coverage) gate coverage run_coverage ;;
    dead-code)
      printf 'GATE dead-code: SKIP_UNSUPPORTED(public library surface; compiler unused is deny in lib, cargo-shear is unused-deps)\n'
      ;;
    sast) gate sast env CARGO_BUILD_WARNINGS=deny cargo clippy --all-targets --locked -- -D warnings ;;
    dependency-vulnerability) gate dependency-vulnerability cargo deny check advisories ;;
    dependency-policy) gate dependency-policy cargo shear && cargo deny check bans licenses sources ;;
    lock-integrity) gate lock-integrity run_deps_hygiene ;;
    negative-fixtures) gate negative-fixtures bash bad_examples/assert.sh ;;
    mutation) run_mutation ;;
    conformance)
      printf 'GATE conformance: SKIP_UNSUPPORTED(adapter not yet wired to shared JSON vectors)\n'
      ;;
    reproducibility)
      printf 'GATE reproducibility: SKIP_UNSUPPORTED(two-clean-build comparison is root evidence)\n'
      ;;
    *)
      printf 'internal error: unhandled capability %s\n' "${phase}" >&2
      exit 64
      ;;
  esac
done
