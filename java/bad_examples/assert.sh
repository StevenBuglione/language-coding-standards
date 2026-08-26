#!/usr/bin/env bash
# Negative fixtures: every gate must demonstrably bite (CONTRACTS.md §3).
#
# Manifest (fixture -> gate -> expected stable signal):
# +----------------------+----------+------------------------------------------+
# | fixture              | gate     | expected signal                          |
# +----------------------+----------+------------------------------------------+
# | Misformatted         | format   | spotless "format violations"             |
# | TypesViolation.greet | types    | "[NullAway]" nullability diagnostic      |
# | TypesViolation       | types    | "BoxedPrimitiveEquality" Error Prone ID  |
# | StyleViolation       | lint     | checkstyle "AvoidStarImport"             |
# | StyleViolation       | lint     | checkstyle "RegexpSingleline" (print)    |
# | PmdViolation         | lint     | PMD rule "ExcessiveParameterList"        |
# | SecurityViolation    | security | findsecbugs bug pattern HARD_CODE_PASSWORD|
# | LoyalDomainService   | arch     | ArchUnit "Architecture Violation"        |
# +----------------------+----------+------------------------------------------+
#
# One standalone Maven project holds all fixtures; each analyzer is invoked
# SEPARATELY and scoped to its fixture via the fixture.include /
# fixture.test.include properties, so a compile-breaking fixture cannot mask
# a later analyzer's signal. target/ is wiped between invocations to keep
# every run independent of the previous one.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

export MAVEN_USER_HOME="${PWD}/.m2wrapper"

declare -a FAILURES=()

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

# Runs one analyzer invocation against the bad_examples project with the
# given include scoping; wipes target/ first so runs stay independent.
bad_mvn() {
  local include="$1" test_include="$2"
  shift 2
  rm -rf bad_examples/target
  (
    cd bad_examples &&
      ../mvnw -B --no-transfer-progress -Dmaven.repo.local="${PWD}/../.m2repo" \
        "-Dfixture.include=${include}" "-Dfixture.test.include=${test_include}" "$@"
  )
}

# PMD prints rule names only into its XML report, never onto the console, so
# run the scan then surface the report for signal matching — preserving the
# build's nonzero exit as the function's own.
pmd_fixture() {
  local rc
  bad_mvn '**/*.java' nothing pmd:pmd pmd:check
  rc=$?
  cat bad_examples/target/pmd.xml
  return "${rc}"
}

expect_failure unformatted 'format violations' \
  bad_mvn '**/format/*.java' nothing spotless:check
expect_failure nullaway_nullability '\[NullAway\]' \
  bad_mvn '**/types/*.java' nothing compile
expect_failure ep_boxed_equality 'BoxedPrimitiveEquality' \
  bad_mvn '**/types/*.java' nothing compile
expect_failure checkstyle_star_imports 'AvoidStarImport' \
  bad_mvn '**/*.java' nothing checkstyle:check
expect_failure checkstyle_printing 'RegexpSingleline.*System.out printing' \
  bad_mvn '**/*.java' nothing checkstyle:check
expect_failure pmd_parameter_bloat 'ExcessiveParameterList' \
  pmd_fixture
expect_failure spotbugs_hardcoded_password 'HARD_CODE_PASSWORD' \
  bad_mvn '**/security/*.java' nothing compile spotbugs:check
expect_failure arch_domain_reaches_adapter 'Architecture Violation' \
  bad_mvn '**/arch/**/*.java' '**/arch/*.java' test '-Dsurefire.failIfNoSpecifiedTests=false'

if ((${#FAILURES[@]} > 0)); then
  printf 'FAILED fixtures:\n'
  printf '  - %s\n' "${FAILURES[@]}"
  exit 1
fi
printf 'All negative fixtures caught.\n'
