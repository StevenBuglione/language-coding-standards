#!/usr/bin/env bash
# Canonical gate runner for the TypeScript template (CONTRACTS.md §1).
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

enable_pnpm() {
  # Corepack ships with Node 24 (removed only in Node 25+) and resolves the
  # exact pnpm version pinned by packageManager in package.json.
  #
  # Runs unconditionally at startup: CI splits the phase set across jobs
  # (CONTRACTS.md §5), each in a fresh container, so pnpm availability can
  # never depend on the deps phase having run in the same container.
  corepack enable pnpm >/dev/null 2>&1 || true
}

enable_pnpm

run_deps() {
  pnpm install --frozen-lockfile
}

run_security() {
  # No production runtime dependency exists in this template (everything is
  # devDependencies), so --prod audits exactly what would ship: an empty set
  # must still pass cleanly. The honest gap — no free TS SAST — is documented
  # in LANG_SPEC.md's non-enforcements table.
  pnpm audit --prod --audit-level high
}

run_deps_hygiene() {
  # A frozen-lockfile install is idempotent by contract: it must succeed
  # when manifest and lockfile agree, fail loudly when they drift, and in
  # both cases leave pnpm-lock.yaml byte-identical. The hash guard proves
  # the no-mutation half directly — the compose mount exposes the template
  # directory without .git metadata, so a git-based guard cannot run here
  # (and a hash never fights CRLF normalization across platforms).
  #
  # errexit is suspended inside gate()'s `|| rc=$?` capture, so every
  # fallible step here must fail explicitly instead of falling through.
  local before after
  before="$(sha256sum pnpm-lock.yaml)"
  if ! pnpm install --frozen-lockfile; then
    printf 'frozen-lockfile install failed\n' >&2
    return 1
  fi
  after="$(sha256sum pnpm-lock.yaml)"
  if [[ "${before}" != "${after}" ]]; then
    printf 'pnpm install mutated pnpm-lock.yaml\n' >&2
    return 1
  fi
}

run_mutation() {
  if [[ "${VERIFY_TIER:-}" == "full" ]]; then
    # Nightly tier: StrykerJS runs with its own break threshold from
    # stryker.config.json (break=70); a score below it exits nonzero and
    # fails the gate without any output parsing here.
    local log rc
    log="$(mktemp)"
    rc=0
    pnpm exec stryker run >"${log}" 2>&1 || rc=$?
    tail -n 40 "${log}" >&2 || true
    rm -f "${log}"
    if ((rc != 0)); then
      printf 'GATE mutation: FAIL (stryker exited %s)\n' "${rc}"
      exit "${rc}"
    fi
    printf 'GATE mutation: PASS\n'
  else
    printf 'GATE mutation: SKIP (nightly tier only)\n'
  fi
}

phase_list="$(select_phases "$@")" || exit $?
mapfile -t phases <<<"${phase_list}"

for phase in "${phases[@]}"; do
  case "${phase}" in
    deps) gate deps run_deps ;;
    format) gate format pnpm exec prettier --check . ;;
    lint) gate lint pnpm exec eslint . --report-unused-disable-directives ;;
    types) gate types pnpm exec tsc --noEmit ;;
    arch) gate arch pnpm exec depcruise src ;;
    test) gate test pnpm exec vitest run ;;
    coverage) gate coverage pnpm exec vitest run --coverage ;;
    deadcode) gate deadcode pnpm exec knip ;;
    # run_security wraps the audit so a failed invocation prints
    # "GATE security: FAIL (...)" instead of dying under set -e silently.
    security) gate security run_security ;;
    deps-hygiene) gate deps-hygiene run_deps_hygiene ;;
    negative) gate negative bash bad_examples/assert.sh ;;
    mutation) run_mutation ;;
  esac
done
