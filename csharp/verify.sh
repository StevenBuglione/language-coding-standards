#!/usr/bin/env bash
# Canonical gate runner for the C# template (CONTRACTS.md §1).
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

# Hermetic caches stay inside the mounted workspace (CONTRACTS.md §4).
mkdir -p .nuget/packages .nuget/http-cache .dotnet .cache
export NUGET_PACKAGES="${PWD}/.nuget/packages"
export NUGET_HTTP_CACHE_PATH="${PWD}/.nuget/http-cache"
export DOTNET_CLI_HOME="${PWD}/.dotnet"
export DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
export DOTNET_NOLOGO=1
export DOTNET_CLI_TELEMETRY_OPTOUT=1
export DOTNET_GENERATE_ASPNET_CERTIFICATE=false
export XDG_CACHE_HOME="${PWD}/.cache"

readonly SOLUTION="Warehouse.sln"

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

run_bootstrap() {
  if compgen -G "src/*/packages.lock.json" >/dev/null; then
    dotnet restore "${SOLUTION}" --locked-mode
  else
    dotnet restore "${SOLUTION}" --use-lock-file
  fi
}

run_tests() {
  local project="$1"
  local filter="${2:-}"
  local log rc
  log="$(mktemp)"
  rc=0
  if [[ -n "${filter}" ]]; then
    dotnet test "${project}" --no-restore -c Release --nologo --filter "${filter}" >"${log}" 2>&1 || rc=$?
  else
    dotnet test "${project}" --no-restore -c Release --nologo >"${log}" 2>&1 || rc=$?
  fi
  cat "${log}" >&2
  if ((rc != 0)); then
    rm -f "${log}"
    return "${rc}"
  fi
  if ! grep -qE 'Passed:[[:space:]]*[1-9]' "${log}"; then
    printf 'zero tests executed in %s\n' "${project}" >&2
    rm -f "${log}"
    return 1
  fi
  rm -f "${log}"
}

run_package() {
  local tmp nupkg
  tmp="$(mktemp -d)"
  if ! dotnet pack src/Warehouse.Domain/Warehouse.Domain.csproj --no-restore -c Release -o "${tmp}/nupkg"; then
    rm -rf "${tmp}"
    return 1
  fi
  shopt -s nullglob
  local packages=("${tmp}/nupkg"/Warehouse.Domain.*.nupkg)
  shopt -u nullglob
  nupkg="${packages[0]:-}"
  if [[ -z "${nupkg}" ]]; then
    printf 'dotnet pack produced no nupkg\n' >&2
    rm -rf "${tmp}"
    return 1
  fi
  mkdir -p "${tmp}/consumer"
  cat >"${tmp}/consumer/Consumer.csproj" <<'EOF'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net9.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
    <ManagePackageVersionsCentrally>false</ManagePackageVersionsCentrally>
    <RestorePackagesWithLockFile>false</RestorePackagesWithLockFile>
    <TreatWarningsAsErrors>false</TreatWarningsAsErrors>
    <NuGetAudit>false</NuGetAudit>
    <EnableNETAnalyzers>false</EnableNETAnalyzers>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Warehouse.Domain" Version="1.0.0" />
  </ItemGroup>
</Project>
EOF
  cat >"${tmp}/consumer/Program.cs" <<'EOF'
using Warehouse.Domain;
var money = new Money(0, "USD");
if (money.Currency != "USD")
{
    throw new System.Exception("smoke failed");
}
EOF
  cat >"${tmp}/consumer/nuget.config" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="local" value="${tmp}/nupkg" />
  </packageSources>
</configuration>
EOF
  local rc=0
  (
    cd "${tmp}/consumer"
    dotnet restore Consumer.csproj
    dotnet run --no-restore --nologo
  ) || rc=$?
  rm -rf "${tmp}"
  return "${rc}"
}

run_vulnerable() {
  local out
  out="$(mktemp)"
  if ! dotnet list "${SOLUTION}" package --vulnerable --include-transitive >"${out}" 2>&1; then
    if grep -qiE 'does not have a command|unknown option|No such command|unrecognized' "${out}"; then
      cat "${out}" >&2
      rm -f "${out}"
      printf 'GATE dependency-vulnerability: SKIP_UNSUPPORTED(dotnet list package --vulnerable not available)\n'
      return 0
    fi
    cat "${out}" >&2
    rm -f "${out}"
    printf 'GATE dependency-vulnerability: FAIL (exit 1)\n'
    return 1
  fi
  cat "${out}" >&2
  if grep -qE 'has the following vulnerable packages' "${out}"; then
    rm -f "${out}"
    printf 'GATE dependency-vulnerability: FAIL (vulnerable packages reported)\n'
    return 1
  fi
  rm -f "${out}"
  printf 'GATE dependency-vulnerability: PASS\n'
}

cap_list="$(expand_capabilities "$@")" || { usage; exit 64; }
mapfile -t phases <<<"${cap_list}"

for phase in "${phases[@]}"; do
  case "${phase}" in
    bootstrap) gate bootstrap run_bootstrap ;;
    format) gate format dotnet format "${SOLUTION}" --verify-no-changes ;;
    lint)
      printf 'GATE lint: SKIP_UNSUPPORTED(Roslyn code-style analyzers run during compile via EnforceCodeStyleInBuild)\n'
      ;;
    compile) gate compile dotnet build "${SOLUTION}" --no-restore -c Release -warnaserror ;;
    architecture)
      gate architecture run_tests tests/Warehouse.IntegrationTests/Warehouse.IntegrationTests.csproj 'FullyQualifiedName~ArchitectureTests'
      ;;
    unit) gate unit run_tests tests/Warehouse.UnitTests/Warehouse.UnitTests.csproj ;;
    property) gate property run_tests tests/Warehouse.PropertyTests/Warehouse.PropertyTests.csproj ;;
    integration)
      gate integration run_tests tests/Warehouse.IntegrationTests/Warehouse.IntegrationTests.csproj 'FullyQualifiedName~PlaceOrderTests'
      ;;
    package) gate package run_package ;;
    coverage)
      printf 'GATE coverage: SKIP_UNSUPPORTED(coverlet / Testing Platform coverage not yet wired)\n'
      ;;
    dead-code)
      printf 'GATE dead-code: SKIP_UNSUPPORTED(IDE0005 unused usings run as analyzers during compile; no dedicated reachability scanner)\n'
      ;;
    sast) gate sast dotnet build "${SOLUTION}" --no-restore -c Release -warnaserror ;;
    dependency-vulnerability) run_vulnerable || exit 1 ;;
    dependency-policy)
      printf 'GATE dependency-policy: SKIP_UNSUPPORTED(no license/unused-dependency policy tool in this experimental pack)\n'
      ;;
    lock-integrity) gate lock-integrity dotnet restore "${SOLUTION}" --locked-mode ;;
    negative-fixtures) gate negative-fixtures bash bad_examples/assert.sh ;;
    mutation)
      printf 'GATE mutation: SKIP_UNSUPPORTED(Stryker.NET not yet trust-reviewed for this pack)\n'
      ;;
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
