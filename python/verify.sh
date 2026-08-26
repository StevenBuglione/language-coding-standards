#!/usr/bin/env bash
# Canonical gate runner for the Python template (CONTRACTS.md §1).
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

run_security() {
  # The synced env contains the local project itself, which PyPI cannot
  # audit; --strict rightly refuses to skip anything. So audit the exact
  # locked pin set instead: exported fresh from uv.lock (--no-emit-project
  # drops only the local root), audited with --strict --no-deps so every
  # third-party package in the environment must resolve cleanly or fail.
  #
  # errexit is suspended inside gate()'s `|| rc=$?` capture, so EVERY
  # fallible step here must fail explicitly: a failed export returns 1
  # instead of falling through to auditing a stale requirements file, and
  # the file is removed upfront so no prior run can leave one behind.
  local reqs=".cache/pip-audit-requirements.txt"
  rm -f "${reqs}"
  mkdir -p .cache
  if ! uv export --locked --no-emit-project --format requirements-txt -o "${reqs}"; then
    printf 'dependency export failed; cannot audit fresh pins\n' >&2
    return 1
  fi
  uv run pip-audit --strict --no-deps -r "${reqs}"
}

run_mutation() {
  if [[ "${VERIFY_TIER:-}" == "full" ]]; then
    # Nightly tier: run the muters, then require a kill score floor. The score
    # line ("killed X of Y") is parsed from the mutmut summary; a missing or
    # unparseable summary fails the gate rather than silently passing.
    local floor="${MUTATION_FLOOR:-70}"
    local log rc killed total score
    log="$(mktemp)"
    rc=0
    uv run mutmut run >"${log}" 2>&1 || rc=$?
    if ((rc != 0)); then
      tail -n 25 "${log}" >&2
      printf 'GATE mutation: FAIL (mutmut exited %s)\n' "${rc}"
      exit "${rc}"
    fi
    killed="$(grep -oE '[0-9]+ survived|[0-9]+ killed' "${log}" | grep killed | grep -oE '[0-9]+' || true)"
    total="$(grep -oE '[0-9]+ of [0-9]+' "${log}" | grep -oE '[0-9]+$' || true)"
    if [[ -z "${killed}" || -z "${total}" || "${total}" -eq 0 ]]; then
      tail -n 25 "${log}" >&2
      printf 'GATE mutation: FAIL (no parsable mutmut summary)\n'
      exit 1
    fi
    score=$((100 * killed / total))
    rm -f "${log}"
    if ((score >= floor)); then
      printf 'GATE mutation: PASS\n'
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
    deps) gate deps uv sync --locked ;;
    format) gate format uv run ruff format --check . ;;
    lint) gate lint uv run ruff check . ;;
    types) gate types uv run basedpyright ;;
    arch) gate arch uv run lint-imports ;;
    test) gate test uv run pytest tests/unit tests/integration -q ;;
    coverage) CI=true gate coverage uv run pytest tests -q --cov=warehouse --cov-branch --cov-report=term-missing ;;
    deadcode) gate deadcode uv run vulture src vulture_whitelist.py --min-confidence 80 ;;
    # Export AND audit both run inside the gate: a failed uv export must
    # print "GATE security: FAIL (...)", never die under set -e silently.
    security) gate security run_security ;;
    deps-hygiene) gate deps-hygiene uv lock --check ;;
    negative) gate negative bash bad_examples/assert.sh ;;
    mutation) run_mutation ;;
  esac
done
