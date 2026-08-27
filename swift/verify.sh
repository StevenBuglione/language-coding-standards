#!/usr/bin/env bash
# Canonical gate runner for the Swift template (CONTRACTS.md §1).
#
# Usage:
#   ./verify.sh              # all phases, canonical order
#   ./verify.sh [phase...]   # subset, still canonical order
#
# Prints exactly one "GATE <phase>: PASS" line per phase on stdout; tool
# diagnostics go to stderr. Exits nonzero at the first failing phase.
# Evidence is Linux (`swift:6.0`). Apple platforms are unproven.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=capabilities.sh
source ./capabilities.sh

# Container preamble (CONTRACTS.md §5): trust the mounted workspace.
git config --global --add safe.directory "${GITHUB_WORKSPACE:-/workspace}" >/dev/null 2>&1 || true

# Hermetic caches stay inside the mounted workspace (CONTRACTS.md §5).
mkdir -p .cache .build
export XDG_CACHE_HOME="${PWD}/.cache"

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

have_swift_format() {
  swift format --help >/dev/null 2>&1
}

run_format() {
  if ! swift format lint --strict --recursive Sources Tests; then
    return 1
  fi
  swift format lint --strict Package.swift
}

tests_ran() {
  local output="$1"
  grep -qE 'Test run with [1-9][0-9]* tests|Executed [1-9][0-9]* tests' <<<"${output}"
}

run_unit() {
  local output rc
  rc=0
  output="$(swift test 2>&1)" || rc=$?
  printf '%s\n' "${output}" >&2
  if ((rc != 0)); then
    return "${rc}"
  fi
  if ! tests_ran "${output}"; then
    printf 'zero tests executed\n' >&2
    return 1
  fi
}

run_package() {
  if ! swift build -c release; then
    printf 'swift build -c release failed\n' >&2
    return 1
  fi
  local tmp
  tmp="$(mktemp -d)"
  mkdir -p "${tmp}/Consumer/Sources/Consumer"
  cat >"${tmp}/Consumer/Package.swift" <<EOF
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
  name: "Consumer",
  dependencies: [.package(path: "${PWD}")],
  targets: [.executableTarget(name: "Consumer", dependencies: [.product(name: "Warehouse", package: "Warehouse")])]
)
EOF
  printf 'import Warehouse\n@main struct Run { static func main() { _ = try? Money(minorUnits: 0, currency: "ZZZ") } }\n' \
    >"${tmp}/Consumer/Sources/Consumer/main.swift"
  (
    cd "${tmp}/Consumer"
    swift build
  )
}

cap_list="$(expand_capabilities "$@")" || { usage; exit 64; }
mapfile -t phases <<<"${cap_list}"

for phase in "${phases[@]}"; do
  case "${phase}" in
    bootstrap) gate bootstrap swift package resolve ;;
    format)
      if have_swift_format; then
        gate format run_format
      else
        printf 'GATE format: SKIP_UNSUPPORTED(swift format not available on this toolchain)\n'
      fi
      ;;
    lint)
      printf 'GATE lint: SKIP_UNSUPPORTED(no SwiftLint or equivalent pinned in this experimental pack)\n'
      ;;
    compile) gate compile swift build --build-tests ;;
    architecture) gate architecture swift test --filter ArchitectureTests ;;
    unit) gate unit swift test --filter 'MoneyTests|QuantityTests|SkuTests|OrderTests|ConformanceTests|PropertyTests|ArchitectureTests' ;;
    property) gate property swift test --filter PropertyTests ;;
    integration) gate integration swift test --filter PlaceOrderTests ;;
    package) gate package run_package ;;
    coverage)
      printf 'GATE coverage: SKIP_UNSUPPORTED(swift test --enable-code-coverage floors not parsed yet)\n'
      ;;
    dead-code)
      printf 'GATE dead-code: SKIP_UNSUPPORTED(no unreachable-declaration detector wired yet)\n'
      ;;
    sast)
      printf 'GATE sast: SKIP_UNSUPPORTED(no source-level security scanner wired yet)\n'
      ;;
    dependency-vulnerability)
      printf 'GATE dependency-vulnerability: SKIP_UNSUPPORTED(no SwiftPM advisory scanner wired yet)\n'
      ;;
    dependency-policy)
      printf 'GATE dependency-policy: SKIP_UNSUPPORTED(no license/source policy tool wired yet)\n'
      ;;
    lock-integrity) gate lock-integrity test -f Package.resolved ;;
    negative-fixtures) gate negative-fixtures bash bad_examples/assert.sh ;;
    mutation)
      printf 'GATE mutation: SKIP_UNSUPPORTED(no trustworthy Swift mutator; do not simulate one)\n'
      ;;
    conformance) gate conformance swift test --filter ConformanceTests ;;
    reproducibility)
      printf 'GATE reproducibility: SKIP_UNSUPPORTED(two-clean-build comparison is WP7 root evidence)\n'
      ;;
    *)
      printf 'internal error: unhandled capability %s\n' "${phase}" >&2
      exit 64
      ;;
  esac
done
