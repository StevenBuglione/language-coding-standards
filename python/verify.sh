#!/usr/bin/env bash
# Canonical gate runner for the Python template (CONTRACTS.md §1).
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

readonly REQUIRED_PYTHON_MINOR="3.13"
readonly REQUIRED_UV_VERSION="0.12.6"
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

uv_run() {
  # uv otherwise re-locks automatically before executing. --locked turns any
  # metadata/lock drift into an error instead of mutating evidence during CI.
  uv run --locked "$@"
}

lock_digest() {
  sha256sum uv.lock | awk '{print $1}'
}

run_bootstrap() {
  local python_minor uv_version
  python_minor="$(python -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
  if [[ "${python_minor}" != "${REQUIRED_PYTHON_MINOR}" ]]; then
    printf 'Python minor %s does not match required %s\n' \
      "${python_minor}" "${REQUIRED_PYTHON_MINOR}" >&2
    return 1
  fi
  uv_version="$(uv --version | awk '{print $2}')"
  if [[ "${uv_version}" != "${REQUIRED_UV_VERSION}" ]]; then
    printf 'uv version %s does not match required %s\n' \
      "${uv_version:-unknown}" "${REQUIRED_UV_VERSION}" >&2
    return 1
  fi
  uv sync --locked
}

run_security() {
  # Audit the exact third-party pin set exported fresh from uv.lock. The local
  # project is omitted because it is not a PyPI distribution.
  local reqs=".cache/pip-audit-requirements.txt"
  rm -f "${reqs}"
  mkdir -p .cache
  if ! uv export --locked --no-emit-project --format requirements-txt -o "${reqs}"; then
    printf 'dependency export failed; cannot audit fresh pins\n' >&2
    return 1
  fi
  uv_run pip-audit --strict --no-deps -r "${reqs}"
}

run_mutation() {
  if [[ "${VERIFY_TIER:-}" != "full" ]]; then
    printf 'GATE mutation: SKIP_UNSUPPORTED(full tier only)\n'
    return 0
  fi
  local log rc killed total score
  log="$(mktemp)"
  rc=0
  uv_run mutmut run >"${log}" 2>&1 || rc=$?
  if ((rc != 0)); then
    tail -n 25 "${log}" >&2
    rm -f "${log}"
    printf 'GATE mutation: FAIL (mutmut exited %s)\n' "${rc}"
    exit "${rc}"
  fi
  killed="$(grep -oE '[0-9]+ survived|[0-9]+ killed' "${log}" | grep killed | grep -oE '[0-9]+' || true)"
  total="$(grep -oE '[0-9]+ of [0-9]+' "${log}" | grep -oE '[0-9]+$' || true)"
  if [[ -z "${killed}" || -z "${total}" || "${total}" -eq 0 ]]; then
    tail -n 25 "${log}" >&2
    rm -f "${log}"
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
  local tmp wheel before after
  if ! uv lock --check; then
    return 1
  fi
  before="$(lock_digest)"
  tmp="$(mktemp -d)"
  # uv 0.12.6 does not expose `uv build --locked`; prove equivalent lock
  # integrity by checking the lock first and rejecting any build-time change.
  if ! uv build --out-dir "${tmp}"; then
    rm -rf "${tmp}"
    return 1
  fi
  after="$(lock_digest)"
  if [[ "${before}" != "${after}" ]]; then
    printf 'uv build mutated uv.lock\n' >&2
    rm -rf "${tmp}"
    return 1
  fi
  wheel="$(find "${tmp}" -name '*.whl' -print -quit)"
  if [[ -z "${wheel}" ]]; then
    printf 'uv build produced no wheel\n' >&2
    rm -rf "${tmp}"
    return 1
  fi
  if ! python -m venv "${tmp}/consumer"; then
    rm -rf "${tmp}"
    return 1
  fi
  # shellcheck disable=SC1091
  source "${tmp}/consumer/bin/activate" 2>/dev/null || source "${tmp}/consumer/Scripts/activate"
  if ! pip install --no-deps "${wheel}"; then
    deactivate || true
    rm -rf "${tmp}"
    return 1
  fi
  if ! python -c "from warehouse.domain.money import Money; assert Money(0, 'USD').currency == 'USD'"; then
    deactivate || true
    rm -rf "${tmp}"
    return 1
  fi
  deactivate || true
  rm -rf "${tmp}"
}

ensure_pytest_collection() {
  local scope="$1" collected rc
  collected=""
  rc=0
  collected="$(uv_run pytest "${scope}" -q --collect-only 2>&1)" || rc=$?
  printf '%s\n' "${collected}" >&2
  if ((rc != 0)); then
    printf 'pytest collection failed under %s\n' "${scope}" >&2
    return "${rc}"
  fi
  if ! grep -qE '[1-9][0-9]* tests? collected' <<<"${collected}"; then
    printf 'zero tests collected under %s\n' "${scope}" >&2
    return 1
  fi
}

run_pytest_scope() {
  local scope="$1"
  shift
  ensure_pytest_collection "${scope}" || return 1
  uv_run pytest "${scope}" "$@"
}

run_coverage() {
  CI=true run_pytest_scope tests -q --cov=warehouse --cov-branch --cov-report=term-missing
}

cap_list="$(expand_capabilities "$@")" || { usage; exit 64; }
mapfile -t phases <<<"${cap_list}"

for phase in "${phases[@]}"; do
  case "${phase}" in
    bootstrap) gate bootstrap run_bootstrap ;;
    format) gate format uv_run ruff format --check . ;;
    lint) gate lint uv_run ruff check . ;;
    compile) gate compile uv_run basedpyright ;;
    architecture) gate architecture uv_run lint-imports ;;
    unit) gate unit run_pytest_scope tests/unit -q ;;
    property) gate property run_pytest_scope tests/property -q ;;
    integration) gate integration run_pytest_scope tests/integration -q ;;
    package) gate package run_package ;;
    coverage) gate coverage run_coverage ;;
    dead-code) gate dead-code uv_run vulture src vulture_whitelist.py --min-confidence 80 ;;
    sast) gate sast uv_run ruff check src --select S ;;
    dependency-vulnerability) gate dependency-vulnerability run_security ;;
    dependency-policy)
      printf 'GATE dependency-policy: SKIP_UNSUPPORTED(lock integrity is separate; no unused-dependency policy tool)\n'
      ;;
    lock-integrity) gate lock-integrity uv lock --check ;;
    negative-fixtures) gate negative-fixtures bash bad_examples/assert.sh ;;
    mutation) run_mutation ;;
    conformance) gate conformance run_pytest_scope tests/conformance -q ;;
    reproducibility)
      printf 'GATE reproducibility: SKIP_UNSUPPORTED(two-clean-build comparison is root evidence)\n'
      ;;
    *)
      printf 'internal error: unhandled capability %s\n' "${phase}" >&2
      exit 64
      ;;
  esac
done
