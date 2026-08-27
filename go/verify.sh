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

# Pinned tool versions: installed fresh by the bootstrap phase, never baked
# into the image. The golangci-lint checksum manifest is itself digest-pinned,
# so bootstrap never executes downloaded shell code.
readonly GOLANGCI_LINT_VERSION="v2.13.1"
readonly GOLANGCI_LINT_CHECKSUMS_SHA256="491b9fce854fdc756f75acd8f8f04661c96135720bcd783a87582ba47932dfa5"
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

verify_sha256() {
  local file="$1" expected="$2" actual
  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "${file}" | awk '{print $1}')"
  elif command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 256 "${file}" | awk '{print $1}')"
  else
    printf 'neither sha256sum nor shasum is available\n' >&2
    return 1
  fi
  if [[ "${actual}" != "${expected}" ]]; then
    printf 'sha256 mismatch for %s: got %s, want %s\n' "${file}" "${actual}" "${expected}" >&2
    return 1
  fi
}

install_golangci_lint() {
  local version os arch archive checksums release_base tmp expected binary
  version="${GOLANGCI_LINT_VERSION#v}"
  case "$(uname -s)" in
    Linux) os="linux" ;;
    Darwin) os="darwin" ;;
    *)
      printf 'unsupported golangci-lint operating system: %s\n' "$(uname -s)" >&2
      return 1
      ;;
  esac
  case "$(uname -m)" in
    x86_64 | amd64) arch="amd64" ;;
    arm64 | aarch64) arch="arm64" ;;
    *)
      printf 'unsupported golangci-lint architecture: %s\n' "$(uname -m)" >&2
      return 1
      ;;
  esac

  archive="golangci-lint-${version}-${os}-${arch}.tar.gz"
  checksums="golangci-lint-${version}-checksums.txt"
  release_base="https://github.com/golangci/golangci-lint/releases/download/${GOLANGCI_LINT_VERSION}"
  tmp="$(mktemp -d)"

  if ! curl --fail --location --silent --show-error \
    --output "${tmp}/${checksums}" "${release_base}/${checksums}"; then
    rm -rf "${tmp}"
    printf 'failed to download golangci-lint checksum manifest\n' >&2
    return 1
  fi
  if ! verify_sha256 "${tmp}/${checksums}" "${GOLANGCI_LINT_CHECKSUMS_SHA256}"; then
    rm -rf "${tmp}"
    return 1
  fi
  expected="$(awk -v name="${archive}" '$2 == name { print $1; exit }' "${tmp}/${checksums}")"
  if [[ -z "${expected}" ]]; then
    rm -rf "${tmp}"
    printf 'checksum manifest has no entry for %s\n' "${archive}" >&2
    return 1
  fi
  if ! curl --fail --location --silent --show-error \
    --output "${tmp}/${archive}" "${release_base}/${archive}"; then
    rm -rf "${tmp}"
    printf 'failed to download %s\n' "${archive}" >&2
    return 1
  fi
  if ! verify_sha256 "${tmp}/${archive}" "${expected}"; then
    rm -rf "${tmp}"
    return 1
  fi
  if ! tar -xzf "${tmp}/${archive}" -C "${tmp}"; then
    rm -rf "${tmp}"
    printf 'failed to extract %s\n' "${archive}" >&2
    return 1
  fi
  binary="${tmp}/golangci-lint-${version}-${os}-${arch}/golangci-lint"
  if [[ ! -x "${binary}" ]]; then
    rm -rf "${tmp}"
    printf 'release archive did not contain executable golangci-lint\n' >&2
    return 1
  fi
  cp "${binary}" "${GOPATH}/bin/golangci-lint"
  chmod 0755 "${GOPATH}/bin/golangci-lint"
  rm -rf "${tmp}"
  golangci-lint version
}

run_deps() {
  # Errexit is suspended inside gate()'s `|| rc=$?` capture, so every
  # fallible step here fails explicitly instead of half-installing tools.
  if ! go mod download; then
    printf 'go mod download failed\n' >&2
    return 1
  fi
  mkdir -p "${GOPATH}/bin"
  if ! install_golangci_lint; then
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
  # TODO/FIXME ban: scope production code only; bad_examples deliberately
  # contains markers for its rejection fixture.
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
  # The full lint phase also runs depguard; this pass gives architecture a
  # separately named proof gate.
  golangci-lint run --default=none -E depguard ./...
}

run_go_tests() {
  local log rc
  log="$(mktemp)"
  rc=0
  go test -json "$@" >"${log}" 2>&1 || rc=$?
  cat "${log}" >&2
  if ((rc != 0)); then
    rm -f "${log}"
    return "${rc}"
  fi
  if ! grep -qE '"Action":"run".*"Test":"[^"]+"' "${log}"; then
    printf 'go test executed zero tests for arguments: %s\n' "$*" >&2
    rm -f "${log}"
    return 1
  fi
  rm -f "${log}"
}

run_unit_tests() {
  run_go_tests -race -shuffle=on -count=1 ./internal/domain || return 1
  run_go_tests -race -shuffle=on -count=1 ./internal/adapters || return 1
  run_go_tests -race -shuffle=on -count=1 ./internal/application
}

run_coverage() {
  # R3 floor rule: floor = measured total - 4, rounded down, minimum 80.
  local floor=92
  rm -f cover.out
  if ! run_go_tests -race -coverprofile=cover.out -covermode=atomic \
    -coverpkg=./internal/... ./...; then
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
  # -test counts functions reachable only from tests as live.
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
  local tmp output rc
  tmp="$(mktemp -d)"
  output=""
  rc=0
  go build -trimpath -o "${tmp}/warehouse" ./cmd/warehouse || rc=$?
  if ((rc == 0)); then
    output="$("${tmp}/warehouse" 2>&1)" || rc=$?
    printf '%s\n' "${output}"
  fi
  if ((rc == 0)) && ! grep -Eq \
    '^placed order [^:]+: 2 x SKU-1000 @ 1999 minor units = 3998 USD \(PAID\)$' \
    <<<"${output}"; then
    printf 'packaged warehouse executable produced unexpected output\n' >&2
    rc=1
  fi
  rm -rf "${tmp}"
  return "${rc}"
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
    unit) gate unit run_unit_tests ;;
    property)
      gate property run_go_tests -count=1 \
        -run '^(TestMoneyAdditionIsCommutative|TestMoneyScalingDistributesOverAddition)$' \
        ./internal/domain
      ;;
    integration)
      gate integration run_go_tests -race -count=1 -run '^TestPlaceOrder' ./internal/application
      ;;
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
      printf 'GATE reproducibility: SKIP_UNSUPPORTED(two-clean-build comparison is root evidence)\n'
      ;;
    *)
      printf 'internal error: unhandled capability %s\n' "${phase}" >&2
      exit 64
      ;;
  esac
done
