#!/usr/bin/env bash
# Canonical gate runner for the Kotlin template (CONTRACTS.md §1).
#
# Usage:
#   ./verify.sh              # all phases, canonical order
#   ./verify.sh [phase...]   # subset, still canonical order
#
# Prints exactly one "GATE <phase>: PASS" line per phase on stdout; tool
# diagnostics go to stderr. Exits nonzero at the first failing phase.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=capabilities.sh
source ./capabilities.sh

# Container preamble (CONTRACTS.md §5): trust the mounted workspace.
git config --global --add safe.directory "${GITHUB_WORKSPACE:-/workspace}" >/dev/null 2>&1 || true

# Tool caches stay inside the mounted workspace (CONTRACTS.md §5).
export GRADLE_USER_HOME="${PWD}/.gradle-home"
mkdir -p "${GRADLE_USER_HOME}"

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

# Prefer the committed wrapper when present; otherwise the image's gradle.
gradle_bin() {
  if [[ -x ./gradlew ]]; then
    ./gradlew --no-daemon --console=plain "$@"
  else
    gradle --no-daemon --console=plain "$@"
  fi
}

run_package() {
  gradle_bin installDist
  local dist bin
  dist="$(find build/install -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  if [[ -z "${dist}" ]]; then
    printf 'installDist produced no distribution\n' >&2
    return 1
  fi
  if [[ -x "${dist}/bin/warehouse" ]]; then
    bin="${dist}/bin/warehouse"
  elif [[ -f "${dist}/bin/warehouse.bat" ]]; then
    bin="${dist}/bin/warehouse.bat"
  else
    printf 'distribution missing warehouse launcher under %s\n' "${dist}" >&2
    return 1
  fi
  local out
  out="$("${bin}")"
  grep -q 'warehouse-ok ZZZ' <<<"${out}"
}

run_unit() {
  gradle_bin unitTest
}

run_integration() {
  gradle_bin integrationTest
}

cap_list="$(expand_capabilities "$@")" || { usage; exit 64; }
mapfile -t phases <<<"${cap_list}"

for phase in "${phases[@]}"; do
  case "${phase}" in
    bootstrap) gate bootstrap gradle_bin compileTestKotlin ;;
    format) gate format gradle_bin ktlintCheck ;;
    lint) gate lint gradle_bin ktlintCheck ;;
    compile) gate compile gradle_bin compileKotlin compileTestKotlin ;;
    architecture)
      printf 'GATE architecture: SKIP_UNSUPPORTED(ArchUnit not yet wired in experimental pack)\n'
      ;;
    unit) gate unit run_unit ;;
    property)
      printf 'GATE property: SKIP_UNSUPPORTED(kotest property not yet wired; jqwik denylisted)\n'
      ;;
    integration) gate integration run_integration ;;
    package) gate package run_package ;;
    coverage)
      printf 'GATE coverage: SKIP_UNSUPPORTED(Kover not yet wired in experimental pack)\n'
      ;;
    dead-code)
      printf 'GATE dead-code: SKIP_UNSUPPORTED(no Kotlin unreachable-code gate wired)\n'
      ;;
    sast)
      printf 'GATE sast: SKIP_UNSUPPORTED(detekt security not yet wired in experimental pack)\n'
      ;;
    dependency-vulnerability)
      printf 'GATE dependency-vulnerability: SKIP_UNSUPPORTED(no pinned JVM advisory scanner in this pack yet)\n'
      ;;
    dependency-policy)
      printf 'GATE dependency-policy: SKIP_UNSUPPORTED(Gradle dependency analysis not yet wired)\n'
      ;;
    lock-integrity)
      printf 'GATE lock-integrity: SKIP_UNSUPPORTED(Gradle dependency locking not yet wired)\n'
      ;;
    negative-fixtures) gate negative-fixtures bash bad_examples/assert.sh ;;
    mutation)
      printf 'GATE mutation: SKIP_UNSUPPORTED(PIT Kotlin bytecode mapping not yet fixture-proven)\n'
      ;;
    conformance)
      printf 'GATE conformance: SKIP_UNSUPPORTED(adapter not yet wired to shared JSON vectors)\n'
      ;;
    reproducibility)
      printf 'GATE reproducibility: SKIP_UNSUPPORTED(two-clean-build comparison is WP7 root evidence)\n'
      ;;
    *)
      printf 'internal error: unhandled capability %s\n' "${phase}" >&2
      exit 64
      ;;
  esac
done
