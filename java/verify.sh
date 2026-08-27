#!/usr/bin/env bash
# Canonical gate runner for the Java template (CONTRACTS.md §1).
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
# shellcheck source=capabilities.sh
source ./capabilities.sh

# Container preamble (CONTRACTS.md §4): trust the mounted workspace.
git config --global --add safe.directory "${GITHUB_WORKSPACE:-/workspace}" >/dev/null 2>&1 || true

# Tool caches stay inside the mounted workspace (CONTRACTS.md §4): the Maven
# local repository lands in gitignored .m2repo and the wrapper distribution
# cache in gitignored .m2wrapper. Nothing leaks outside the workspace or into
# image layers.
export MAVEN_USER_HOME="${PWD}/.m2wrapper"
readonly REPO_FLAG="-Dmaven.repo.local=${PWD}/.m2repo"

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

# Every mvn invocation goes through the wrapper, batch mode, no download
# progress noise, and the workspace-local repository.
mvn() {
  ./mvnw -B --no-transfer-progress "${REPO_FLAG}" "$@"
}

readonly MUTATION_FLOOR=70

run_mutation() {
  if [[ "${VERIFY_TIER:-}" != "full" ]]; then
    printf 'GATE mutation: SKIP_UNSUPPORTED(full tier only)\n'
    return 0
  fi
  mvn -q -DmutationThreshold="${MUTATION_FLOOR}" pitest:mutationCoverage \
    || { printf 'GATE mutation: FAIL (pitest exited %s)\n' "$?" >&2; exit 1; }
  printf 'GATE mutation: PASS\n'
}

run_package() {
  mvn -q -DskipTests package
  test -f target/warehouse-1.0.0.jar
}

cap_list="$(expand_capabilities "$@")" || { usage; exit 64; }
mapfile -t phases <<<"${cap_list}"

for phase in "${phases[@]}"; do
  case "${phase}" in
    bootstrap) gate bootstrap mvn -q dependency:go-offline ;;
    format) gate format mvn spotless:check ;;
    lint) gate lint mvn checkstyle:check pmd:pmd pmd:check ;;
    compile) gate compile mvn test-compile ;;
    architecture) gate architecture mvn test -Dtest=ArchitectureTest ;;
    unit) gate unit mvn test -Dtest=MoneyTest,OrderTest,QuantityTest,SkuTest ;;
    property) gate property mvn test -Dtest=GenerativeMoneyTest ;;
    integration) gate integration mvn test -Dtest=PlaceOrderUseCaseTest,PlaceOrderUseCaseOrchestrationTest ;;
    package) gate package run_package ;;
    coverage) gate coverage mvn verify ;;
    dead-code)
      printf 'GATE dead-code: SKIP_UNSUPPORTED(dependency:analyze is unused-deps, not unreachable code)\n'
      ;;
    sast) gate sast mvn spotbugs:check ;;
    dependency-vulnerability)
      printf 'GATE dependency-vulnerability: SKIP_UNSUPPORTED(no pinned JVM advisory scanner in this pack yet)\n'
      ;;
    dependency-policy) gate dependency-policy mvn enforcer:enforce dependency:analyze-only ;;
    lock-integrity) gate lock-integrity mvn enforcer:enforce ;;
    negative-fixtures) gate negative-fixtures bash bad_examples/assert.sh ;;
    mutation) run_mutation ;;
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
