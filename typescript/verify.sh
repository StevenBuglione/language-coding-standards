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
  # Audit the complete lockfile, including toolchain/devDependencies. An
  # empty production set is not meaningful security coverage.
  pnpm audit --audit-level high
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
  if [[ "${VERIFY_TIER:-}" != "full" ]]; then
    printf 'GATE mutation: SKIP_UNSUPPORTED(full tier only)\n'
    return 0
  fi
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
}

run_package() {
  pnpm exec tsc --pretty false
  local tmp
  tmp="$(mktemp -d)"
  pnpm pack --pack-destination "${tmp}"
  rm -rf "${tmp}"
}

cap_list="$(expand_capabilities "$@")" || { usage; exit 64; }
mapfile -t phases <<<"${cap_list}"

for phase in "${phases[@]}"; do
  case "${phase}" in
    bootstrap) gate bootstrap run_deps ;;
    format) gate format pnpm exec prettier --check . ;;
    lint) gate lint pnpm exec eslint . --report-unused-disable-directives ;;
    compile) gate compile pnpm exec tsc --noEmit ;;
    architecture) gate architecture pnpm exec depcruise src ;;
    unit) gate unit pnpm exec vitest run tests/unit ;;
    property) gate property pnpm exec vitest run tests/property ;;
    integration) gate integration pnpm exec vitest run tests/integration ;;
    package) gate package run_package ;;
    coverage) gate coverage pnpm exec vitest run --coverage ;;
    dead-code) gate dead-code pnpm exec knip ;;
    sast)
      printf 'GATE sast: SKIP_UNSUPPORTED(eslint security plugin not installed; CodeQL is the repo-level SAST)\n'
      ;;
    dependency-vulnerability) gate dependency-vulnerability run_security ;;
    dependency-policy) gate dependency-policy pnpm exec knip ;;
    lock-integrity) gate lock-integrity run_deps_hygiene ;;
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
