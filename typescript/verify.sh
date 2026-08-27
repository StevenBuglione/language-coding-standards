#!/usr/bin/env bash
# Canonical gate runner for the TypeScript template (CONTRACTS.md §1).

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=capabilities.sh
source ./capabilities.sh

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
  corepack enable pnpm >/dev/null 2>&1 || true
}

enable_pnpm

run_deps() {
  pnpm install --frozen-lockfile
}

run_security() {
  # Audit the complete lockfile, including the build/test toolchain.
  pnpm audit --audit-level high
}

run_deps_hygiene() {
  local before after
  before="$(sha256sum pnpm-lock.yaml)"
  pnpm install --frozen-lockfile || return 1
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
  local tmp tarball consumer rc
  tmp="$(mktemp -d)"
  consumer="${tmp}/consumer"
  rm -rf dist
  if ! pnpm exec tsc -p tsconfig.build.json --pretty false; then
    rm -rf "${tmp}" dist
    return 1
  fi
  printf '{"type":"commonjs"}\n' >dist/package.json
  mkdir -p "${tmp}/artifact" "${consumer}/src"
  if ! pnpm pack --pack-destination "${tmp}/artifact"; then
    rm -rf "${tmp}" dist
    return 1
  fi
  tarball="$(find "${tmp}/artifact" -maxdepth 1 -name '*.tgz' -print -quit)"
  if [[ -z "${tarball}" ]]; then
    printf 'pnpm pack produced no tarball\n' >&2
    rm -rf "${tmp}" dist
    return 1
  fi
  local contents required
  contents="$(tar -tzf "${tarball}")" || { rm -rf "${tmp}" dist; return 1; }
  for required in package/dist/index.js package/dist/index.d.ts package/dist/package.json; do
    if ! grep -qx "${required}" <<<"${contents}"; then
      printf 'package is missing required artifact %s\n' "${required}" >&2
      rm -rf "${tmp}" dist
      return 1
    fi
  done
  if grep -q '^package/src/' <<<"${contents}"; then
    printf 'package unexpectedly contains TypeScript source files\n' >&2
    rm -rf "${tmp}" dist
    return 1
  fi
  cat >"${consumer}/package.json" <<'EOF_PACKAGE'
{"name":"warehouse-orders-consumer","private":true,"type":"commonjs"}
EOF_PACKAGE
  cat >"${consumer}/tsconfig.json" <<'EOF_TSCONFIG'
{
  "compilerOptions": {
    "module": "Node16",
    "moduleResolution": "Node16",
    "target": "ES2023",
    "strict": true,
    "skipLibCheck": false,
    "outDir": "dist"
  },
  "include": ["src/**/*.ts"]
}
EOF_TSCONFIG
  cat >"${consumer}/src/index.ts" <<'EOF_CONSUMER'
import { Money } from "warehouse-orders";
const amount = Money.create(0, "ZZZ");
if (amount.minorUnits !== 0 || amount.currency !== "ZZZ") {
  throw new Error("installed package returned an invalid Money value");
}
EOF_CONSUMER
  rc=0
  (
    cd "${consumer}"
    npm install --ignore-scripts --no-audit --no-fund "${tarball}" >/dev/null
  ) || rc=$?
  if ((rc == 0)); then
    pnpm exec tsc -p "${consumer}/tsconfig.json" --pretty false || rc=$?
  fi
  if ((rc == 0)); then
    node "${consumer}/dist/index.js" || rc=$?
  fi
  rm -rf "${tmp}" dist
  return "${rc}"
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
      printf 'GATE sast: SKIP_UNSUPPORTED(custom ESLint security bans exist; CodeQL is the repo-level SAST)\n'
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
      printf 'GATE reproducibility: SKIP_UNSUPPORTED(two-clean-build comparison is root evidence)\n'
      ;;
    *)
      printf 'internal error: unhandled capability %s\n' "${phase}" >&2
      exit 64
      ;;
  esac
done
