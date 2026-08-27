#!/usr/bin/env bash
# Canonical gate runner for the Go template (CONTRACTS.md §1).
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

# Pinned tool versions: installed fresh by the deps phase, never baked into
# the image. Bump all three together after checking golangci-lint linter
# upgrades; the exact pins are the supply-chain contract (LANG_SPEC.md).
readonly GOLANGCI_LINT_VERSION="v2.13.1"
readonly DEADCODE_VERSION="v0.49.0"     # golang.org/x/tools/cmd/deadcode
readonly GOVULNCHECK_VERSION="v1.7.0"   # golang.org/x/vuln/cmd/govulncheck

# Hermetic caches + tool binaries live in gitignored workspace directories
# (CONTRACTS.md §4); nothing leaks outside /workspace or into image layers.
export GOTOOLCHAIN=local
export GOFLAGS=
mkdir -p .gopath .gocache .gomodcache .golangci-cache .cache
export GOPATH="$PWD/.gopath"
export GOCACHE="$PWD/.gocache"
export GOMODCACHE="$PWD/.gomodcache"
export GOLANGCI_LINT_CACHE="$PWD/.golangci-cache"
export XDG_CACHE_HOME="$PWD/.cache"
export PATH="$GOPATH/bin:$PATH"

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

run_deps() {
  # Errexit is suspended inside gate()'s `|| rc=$?` capture, so EVERY
  # fallible step here fails explicitly instead of half-installing tools
  # and letting a later phase fail with a confusing missing-command error.
  if ! go mod download; then
    printf 'go mod download failed\n' >&2
    return 1
  fi
  mkdir -p "${GOPATH}/bin"
  # Official installer script fetched at the SAME exact version tag as the
  # binary it installs -> both script and release are pinned (LANG_SPEC.md
  # documents the supply-chain tradeoff against `go tool` directives).
  if ! curl -sSfL "https://raw.githubusercontent.com/golangci/golangci-lint/${GOLANGCI_LINT_VERSION}/install.sh" |
    sh -s -- -b "${GOPATH}/bin" "${GOLANGCI_LINT_VERSION}"; then
    printf 'golangci-lint %s install failed\n' "${GOLANGCI_LINT_VERSION}" >&2
    return 1
  fi
  # Compiled from source via the checksum-verified module proxy.
  if ! go install "golang.org/x/tools/cmd/deadcode@${DEADCODE_VERSION}"; then
    printf 'deadcode %s install failed\n' "${DEADCODE_VERSION}" >&2
    return 1
  fi
  if ! go install "golang.org/x/vuln/cmd/govulncheck@${GOVULNCHECK_VERSION}"; then
    printf 'govulncheck %s install failed\n' "${GOVULNCHECK_VERSION}" >&2
    return 1
  fi
}

run_lint() {
  if ! golangci-lint run ./...; then
    return 1
  fi
  # TODO/FIXME ban: Go has no native linter for unfinished-work markers that
  # survives config review cleanly, so the ban is a grep INSIDE the lint
  # phase (documented in LANG_SPEC.md). Scope: production code only —
  # bad_examples/ deliberately contains markers for its own fixture.
  local hits
  hits="$(grep -rnE '(TODO|FIXME)' internal cmd || true)"
  if [[ -n "${hits}" ]]; then
    printf '%s\n' "${hits}" >&2
    printf 'TODO/FIXME markers are banned outside bad_examples; finish or ticket the work\n' >&2
    return 1
  fi
}

run_types() {
  if ! go build ./...; then
    return 1
  fi
  go vet ./...
}

run_arch() {
  # Single-linter pass so the boundary contract has a visibly named gate of
  # its own (--default=none -E depguard runs ONLY depguard). The full lint
  # phase also runs depguard; this pass is the architecture gate's home.
  golangci-lint run --default=none -E depguard ./...
}

run_coverage() {
  # R3 floor rule: floor = measured total - 4, rounded down, minimum 80.
  # Baseline measured on first green run: 96% of statements across
  # ./internal/... (the remaining 4% are provably-unreachable defensive
  # branches; see LANG_SPEC.md thresholds). The floor is a committed
  # constant, like the tool pins above — change it in review, not per-run.
  local floor=92
  rm -f cover.out
  # -coverpkg=./internal/... makes every package's test binary instrument the
  # whole internal tree, so the application-level integration test earns
  # credit for the adapters it drives. cmd/ is excluded from the measured
  # scope: it is thin wiring around the library, with no logic of its own.
  if ! go test -race -coverprofile=cover.out -covermode=atomic -coverpkg=./internal/... ./...; then
    return 1
  fi
  local total
  total="$(go tool cover -func=cover.out | awk '/^total:/ {gsub(/%/, "", $3); print $3}')"
  if [[ -z "${total}" ]]; then
    printf 'no parsable coverage total in go tool cover output\n' >&2
    return 1
  fi
  if (( $(awk -v got="${total}" -v want="${floor}" 'BEGIN { print (got < want) }') )); then
    printf 'coverage %s%% is below floor %s%%\n' "${total}" "${floor}" >&2
    return 1
  fi
  printf 'total coverage %s%% >= floor %s%%\n' "${total}" "${floor}"
}

run_deadcode() {
  # -test counts functions reachable only from tests as live: this module is
  # a library-style pipeline exercised through its tests plus one demo main,
  # so test-only reachability is honest liveness here.
  deadcode -test ./...
}

run_deps_hygiene() {
  if ! go mod tidy -diff; then
    return 1
  fi
  go mod verify
}

run_mutation() {
  printf 'GATE mutation: SKIP_UNSUPPORTED(no stable Go mutator; gremlins is 0.x)\n'
}

run_package() {
  go build -o /tmp/warehouse-cmd ./cmd/warehouse
}

cap_list="$(expand_capabilities "$@")" || { usage; exit 64; }
mapfile -t phases <<<"${cap_list}"

for phase in "${phases[@]}"; do
  case "${phase}" in
    bootstrap) gate bootstrap run_deps ;;
    format) gate format golangci-lint fmt --diff cmd internal ;;
    lint) gate lint run_lint ;;
    compile) gate compile run_types ;;
    architecture) gate architecture run_arch ;;
    unit) gate unit go test -race -shuffle=on -count=1 ./internal/domain ./internal/adapters ./internal/application ;;
    property) gate property go test -count=1 ./internal/domain -run 'Commutative|Distributes' ;;
    integration) gate integration go test -race -count=1 ./internal/application -run PlaceOrder ;;
    package) gate package run_package ;;
    coverage) gate coverage run_coverage ;;
    dead-code) gate dead-code run_deadcode ;;
    sast) gate sast golangci-lint run --default=none -E gosec ./... ;;
    dependency-vulnerability) gate dependency-vulnerability govulncheck ./... ;;
    dependency-policy) gate dependency-policy go mod tidy -diff ;;
    lock-integrity) gate lock-integrity go mod verify ;;
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
