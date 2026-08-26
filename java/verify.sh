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

# Container preamble (CONTRACTS.md §4): trust the mounted workspace.
git config --global --add safe.directory "${GITHUB_WORKSPACE:-/workspace}" >/dev/null 2>&1 || true

# Tool caches stay inside the mounted workspace (CONTRACTS.md §4): the Maven
# local repository lands in gitignored .m2repo and the wrapper distribution
# cache in gitignored .m2wrapper. Nothing leaks outside the workspace or into
# image layers.
export MAVEN_USER_HOME="${PWD}/.m2wrapper"
readonly REPO_FLAG="-Dmaven.repo.local=${PWD}/.m2repo"

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

# Every mvn invocation goes through the wrapper, batch mode, no download
# progress noise, and the workspace-local repository.
mvn() {
  ./mvnw -B --no-transfer-progress "${REPO_FLAG}" "$@"
}

run_mutation() {
  if [[ "${VERIFY_TIER:-}" == "full" ]]; then
    # Nightly tier: pitest runs configured-but-unscheduled (roadmap); it
    # enforces its own mutationThreshold floor and fails below it. errexit is
    # suspended inside gate()'s `|| rc=$?` capture; a missing floor property
    # must fail loudly rather than pass silently, so the threshold is passed
    # explicitly here too.
    local floor="${MUTATION_FLOOR:-70}"
    mvn -q -DmutationThreshold="${floor}" pitest:mutationCoverage \
      || { printf 'GATE mutation: FAIL (pitest exited %s)\n' "$?" >&2; exit 1; }
    printf 'GATE mutation: PASS\n'
  else
    printf 'GATE mutation: SKIP (nightly tier only)\n'
  fi
}

phase_list="$(select_phases "$@")" || exit $?
mapfile -t phases <<<"${phase_list}"

for phase in "${phases[@]}"; do
  case "${phase}" in
    # Warm the full plugin+dependency graph into .m2repo so later phases can
    # run hermetically offline-ish; -q keeps the artifact chatter out of logs.
    deps) gate deps mvn -q dependency:go-offline ;;
    format) gate format mvn spotless:check ;;
    lint) gate lint mvn checkstyle:check pmd:pmd pmd:check ;;
    # javac -Werror + Error Prone + NullAway fire here (main AND tests).
    types) gate types mvn test-compile ;;
    arch) gate arch mvn test -Dtest=ArchitectureTest -Dsurefire.failIfNoSpecifiedTests=false ;;
    test) gate test mvn test ;;
    # Full lifecycle under JaCoCo; the check goal is bound to verify with the
    # R3 floors. Runs unit+arch tests again — accepted cost of one canonical
    # lifecycle command (documented in LANG_SPEC.md).
    coverage) gate coverage mvn verify ;;
    deadcode) gate deadcode mvn dependency:analyze-only ;;
    security) gate security mvn spotbugs:check ;;
    # Maven has no lockfile; enforcer (convergence + version-range bans +
    # release-only deps) plus the analyze pass IS the hygiene contract.
    deps-hygiene) gate deps-hygiene mvn enforcer:enforce dependency:analyze-only ;;
    negative) gate negative bash bad_examples/assert.sh ;;
    mutation) run_mutation ;;
  esac
done
