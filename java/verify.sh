#!/usr/bin/env bash
# Canonical gate runner for the Java template (CONTRACTS.md §1).
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

# Container preamble (CONTRACTS.md §4): trust the mounted workspace.
git config --global --add safe.directory "${GITHUB_WORKSPACE:-/workspace}" >/dev/null 2>&1 || true

# Tool caches stay inside the mounted workspace (CONTRACTS.md §4). The
# official Maven image exports MAVEN_CONFIG=/root/.m2; mvnw interprets that
# image-specific value as a command-line argument, so clear it explicitly.
export MAVEN_CONFIG=
export MAVEN_USER_HOME="${PWD}/.m2wrapper"
readonly REPO_FLAG="-Dmaven.repo.local=${PWD}/.m2repo"
readonly REQUIRED_JAVA_VERSION="25"
readonly REQUIRED_MAVEN_VERSION="3.9.16"
readonly MUTATION_FLOOR=70

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

# Every Maven invocation goes through the checksum-pinned wrapper, batch mode,
# no download progress noise, and the workspace-local repository.
mvn() {
  ./mvnw -B --no-transfer-progress "${REPO_FLAG}" "$@"
}

run_bootstrap() {
  local java_version maven_version
  java_version="$(java -XshowSettings:properties -version 2>&1 \
    | awk -F= '/java.specification.version/ {gsub(/[[:space:]]/, "", $2); print $2; exit}')"
  if [[ "${java_version}" != "${REQUIRED_JAVA_VERSION}" ]]; then
    printf 'Java specification version %s does not match required %s\n' \
      "${java_version:-unknown}" "${REQUIRED_JAVA_VERSION}" >&2
    return 1
  fi
  maven_version="$(mvn -v | awk '/Apache Maven/ {print $3; exit}')"
  if [[ "${maven_version}" != "${REQUIRED_MAVEN_VERSION}" ]]; then
    printf 'Maven version %s does not match required %s\n' \
      "${maven_version:-unknown}" "${REQUIRED_MAVEN_VERSION}" >&2
    return 1
  fi
  mvn -q dependency:go-offline
}

run_tests() {
  local selector="$1" total=0 report count
  local -a reports=()
  rm -rf target/surefire-reports
  if ! mvn test -Dtest="${selector}"; then
    return 1
  fi
  shopt -s nullglob
  reports=(target/surefire-reports/TEST-*.xml)
  shopt -u nullglob
  if ((${#reports[@]} == 0)); then
    printf 'Surefire produced no XML reports for selector %s\n' "${selector}" >&2
    return 1
  fi
  for report in "${reports[@]}"; do
    count="$(grep -oE 'tests="[0-9]+"' "${report}" | head -n 1 | grep -oE '[0-9]+' || true)"
    if [[ -z "${count}" ]]; then
      printf 'could not parse test count from %s\n' "${report}" >&2
      return 1
    fi
    total=$((total + count))
  done
  if ((total == 0)); then
    printf 'Surefire executed zero tests for selector %s\n' "${selector}" >&2
    return 1
  fi
  printf 'Surefire executed %d tests for selector %s\n' "${total}" "${selector}"
}

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
  local jar tmp rc
  jar="${PWD}/.m2repo/com/warehouse/warehouse/1.0.0/warehouse-1.0.0.jar"
  if ! mvn -q -DskipTests install; then
    return 1
  fi
  if [[ ! -f "${jar}" ]]; then
    printf 'installed package is missing: %s\n' "${jar}" >&2
    return 1
  fi
  if ! jar tf "${jar}" | grep -qx 'com/warehouse/domain/Money.class'; then
    printf 'installed package does not contain Money.class\n' >&2
    return 1
  fi

  tmp="$(mktemp -d)"
  cat >"${tmp}/Consumer.java" <<'EOF_CONSUMER'
import com.warehouse.domain.Money;

public final class Consumer {
  private Consumer() {}

  public static void main(String[] args) {
    Money amount = new Money(0L, "ZZZ");
    if (amount.minorUnits() != 0L || !"ZZZ".equals(amount.currency())) {
      throw new IllegalStateException("installed package returned invalid money");
    }
  }
}
EOF_CONSUMER
  rc=0
  javac --release 25 -Werror -cp "${jar}" -d "${tmp}" "${tmp}/Consumer.java" || rc=$?
  if ((rc == 0)); then
    java -cp "${tmp}:${jar}" Consumer || rc=$?
  fi
  rm -rf "${tmp}"
  return "${rc}"
}

cap_list="$(expand_capabilities "$@")" || { usage; exit 64; }
mapfile -t phases <<<"${cap_list}"

for phase in "${phases[@]}"; do
  case "${phase}" in
    bootstrap) gate bootstrap run_bootstrap ;;
    format) gate format mvn spotless:check ;;
    lint) gate lint mvn checkstyle:check pmd:pmd pmd:check ;;
    compile) gate compile mvn test-compile ;;
    architecture) gate architecture run_tests ArchitectureTest ;;
    unit) gate unit run_tests MoneyTest,OrderTest,QuantityTest,SkuTest ;;
    property) gate property run_tests GenerativeMoneyTest ;;
    integration)
      gate integration run_tests PlaceOrderUseCaseTest,PlaceOrderUseCaseOrchestrationTest
      ;;
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
      printf 'GATE reproducibility: SKIP_UNSUPPORTED(two-clean-build comparison is root evidence)\n'
      ;;
    *)
      printf 'internal error: unhandled capability %s\n' "${phase}" >&2
      exit 64
      ;;
  esac
done
