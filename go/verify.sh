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

run_deps() {
  # Errexit is suspended inside gate()'s `|| rc=$?` capture, so EVERY
  # fallible step here fails explicitly instead of half-installing tools
  # and letting a later phase fail with a confusing missing-command error.
  if ! go mod download; then
    printf 'go mod download failed\n' >&2
    return 1
  fi
  mkdir -p "${GOPATH}/bin"
  # Official installer script at an exact version tag -> pinned release
  # binary into $GOPATH/bin (LANG_SPEC.md documents the supply-chain
  # tradeoff against `go tool` directives).
  if ! curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/HEAD/install.sh |
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
  # branches; see LANG_SPEC.md thresholds). Override via COVERAGE_FLOOR only
  # when re-measuring deliberately.
  local floor="${COVERAGE_FLOOR:-92}"
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
  # Mutation roadmap: gremlins (https://github.com/go-gremlins/gremlins) is
  # the candidate mutator but still 0.x/unstable, so no kill-score floor is
  # enforced on any tier yet — a permanently red nightly would just teach
  # everyone to ignore red. When gremlins ships a stable release, replace
  # this block with a `gremlins unleash` run whose kill score is parsed and
  # floored exactly like python's mutmut gate in ../python/verify.sh.
  if [[ "${VERIFY_TIER:-}" == "full" ]]; then
    printf 'GATE mutation: SKIP (no stable Go mutator exists yet; gremlins is 0.x — see LANG_SPEC.md roadmap)\n'
  else
    printf 'GATE mutation: SKIP (nightly tier only)\n'
  fi
}

phase_list="$(select_phases "$@")" || exit $?
mapfile -t phases <<<"${phase_list}"

for phase in "${phases[@]}"; do
  case "${phase}" in
    deps) gate deps run_deps ;;
    # Explicit dirs, not ./...: golangci-lint fmt walks directories directly
    # and would otherwise reach into bad_examples/, which must stay excluded
    # from every main gate by construction (CONTRACTS.md §3).
    format) gate format golangci-lint fmt --diff cmd internal ;;
    lint) gate lint run_lint ;;
    types) gate types run_types ;;
    arch) gate arch run_arch ;;
    test) gate test go test -race -shuffle=on -count=1 ./... ;;
    coverage) gate coverage run_coverage ;;
    deadcode) gate deadcode run_deadcode ;;
    security) gate security govulncheck ./... ;;
    deps-hygiene) gate deps-hygiene run_deps_hygiene ;;
    negative) gate negative bash bad_examples/assert.sh ;;
    mutation) run_mutation ;;
  esac
done
