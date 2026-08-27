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
# shellcheck source=capabilities.sh
source ./capabilities.sh

# Container preamble (CONTRACTS.md §4): trust the mounted workspace.
git config --global --add safe.directory "${GITHUB_WORKSPACE:-/workspace}" >/dev/null 2>&1 || true

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

readonly MUTATION_FLOOR=70

run_mutation() {
  if [[ "${VERIFY_TIER:-}" != "full" ]]; then
    printf 'GATE mutation: SKIP_UNSUPPORTED(full tier only)\n'
    return 0
  fi
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
  if ((score >= MUTATION_FLOOR)); then
    printf 'GATE mutation: PASS\n'
  else
    printf 'GATE mutation: FAIL (score %d < floor %d)\n' "${score}" "${MUTATION_FLOOR}"
    exit 1
  fi
}

run_package() {
  local tmp
  tmp="$(mktemp -d)"
  if ! uv build --out-dir "${tmp}"; then
    rm -rf "${tmp}"
    return 1
  fi
  local wheel
  wheel="$(find "${tmp}" -name '*.whl' | head -n 1)"
  if [[ -z "${wheel}" ]]; then
    printf 'uv build produced no wheel\n' >&2
    rm -rf "${tmp}"
    return 1
  fi
  python -m venv "${tmp}/consumer"
  # shellcheck disable=SC1091
  source "${tmp}/consumer/bin/activate" 2>/dev/null || source "${tmp}/consumer/Scripts/activate"
  if ! pip install --no-deps "${wheel}"; then
    deactivate || true
    rm -rf "${tmp}"
    return 1
  fi
  python -c "from warehouse.domain.money import Money; Money(0, 'USD')"
  deactivate || true
  rm -rf "${tmp}"
}

run_pytest_dir() {
  local dir="$1"
  local collected
  collected="$(uv run pytest "${dir}" -q --collect-only)"
  if ! grep -qE '[1-9][0-9]* tests collected' <<<"${collected}"; then
    printf 'zero tests collected under %s\n' "${dir}" >&2
    return 1
  fi
  uv run pytest "${dir}" -q
}

cap_list="$(expand_capabilities "$@")" || { usage; exit 64; }
mapfile -t phases <<<"${cap_list}"

for phase in "${phases[@]}"; do
  case "${phase}" in
    bootstrap) gate bootstrap uv sync --locked ;;
    format) gate format uv run ruff format --check . ;;
    lint) gate lint uv run ruff check . ;;
    compile) gate compile uv run basedpyright ;;
    architecture) gate architecture uv run lint-imports ;;
    unit) gate unit run_pytest_dir tests/unit ;;
    property) gate property run_pytest_dir tests/property ;;
    integration) gate integration run_pytest_dir tests/integration ;;
    package) gate package run_package ;;
    coverage) CI=true gate coverage uv run pytest tests -q --cov=warehouse --cov-branch --cov-report=term-missing ;;
    dead-code) gate dead-code uv run vulture src vulture_whitelist.py --min-confidence 80 ;;
    sast) gate sast uv run ruff check src --select S ;;
    dependency-vulnerability) gate dependency-vulnerability run_security ;;
    dependency-policy)
      printf 'GATE dependency-policy: SKIP_UNSUPPORTED(lock integrity is separate; no unused-dependency policy tool)\n'
      ;;
    lock-integrity) gate lock-integrity uv lock --check ;;
    negative-fixtures) gate negative-fixtures bash bad_examples/assert.sh ;;
    mutation) run_mutation ;;
    conformance) gate conformance uv run pytest tests/conformance -q ;;
    reproducibility)
      printf 'GATE reproducibility: SKIP_UNSUPPORTED(two-clean-build comparison is WP7 root evidence)\n'
      ;;
    *)
      printf 'internal error: unhandled capability %s\n' "${phase}" >&2
      exit 64
      ;;
  esac
done
