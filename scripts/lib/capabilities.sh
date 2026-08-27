# Capability name expander (CONTRACTS.md §1.2).
# Sourced by each language verify.sh. Also runnable:
#   bash capabilities.sh [--default] [name...]
#
# Exit 64 on unknown name or duplicate after expansion.
# Canonical order is independent of argument order.

CANONICAL_CAPABILITIES=(
  bootstrap
  format
  lint
  compile
  architecture
  unit
  property
  integration
  package
  coverage
  dead-code
  sast
  dependency-vulnerability
  dependency-policy
  lock-integrity
  negative-fixtures
  mutation
  conformance
  reproducibility
)

DEFAULT_CAPABILITIES=(
  bootstrap
  format
  lint
  compile
  architecture
  unit
  property
  integration
  package
  coverage
  dead-code
  sast
  dependency-vulnerability
  dependency-policy
  lock-integrity
  negative-fixtures
)

expand_alias() {
  case "$1" in
    bootstrap | format | lint | compile | architecture | unit | property | integration | package | coverage | sast | mutation | conformance | reproducibility)
      printf '%s\n' "$1"
      ;;
    dead-code | deadcode)
      printf '%s\n' "dead-code"
      ;;
    dependency-vulnerability)
      printf '%s\n' "dependency-vulnerability"
      ;;
    dependency-policy)
      printf '%s\n' "dependency-policy"
      ;;
    lock-integrity)
      printf '%s\n' "lock-integrity"
      ;;
    negative-fixtures | negative)
      printf '%s\n' "negative-fixtures"
      ;;
    deps)
      printf '%s\n' "bootstrap" "lock-integrity"
      ;;
    types)
      printf '%s\n' "compile"
      ;;
    arch)
      printf '%s\n' "architecture"
      ;;
    test)
      printf '%s\n' "unit" "property" "integration"
      ;;
    security)
      printf '%s\n' "sast" "dependency-vulnerability"
      ;;
    deps-hygiene)
      printf '%s\n' "dependency-policy" "lock-integrity"
      ;;
    *)
      printf 'unknown capability: %s\n' "$1" >&2
      return 64
      ;;
  esac
}

expand_capabilities() {
  local requested=()
  if (($# == 0)); then
    printf '%s\n' "${DEFAULT_CAPABILITIES[@]}"
    return 0
  fi
  local arg expanded
  for arg in "$@"; do
    if [[ "${arg}" == "--default" ]]; then
      printf '%s\n' "${DEFAULT_CAPABILITIES[@]}"
      return 0
    fi
    expanded="$(expand_alias "${arg}")" || return 64
    while IFS= read -r item; do
      [[ -z "${item}" ]] && continue
      requested+=("${item}")
    done <<<"${expanded}"
  done

  local seen="|"
  local item
  for item in "${requested[@]}"; do
    if [[ "${seen}" == *"|${item}|"* ]]; then
      printf 'duplicate capability: %s\n' "${item}" >&2
      return 64
    fi
    seen+="${item}|"
  done

  local ordered=()
  local canonical
  for canonical in "${CANONICAL_CAPABILITIES[@]}"; do
    for item in "${requested[@]}"; do
      if [[ "${item}" == "${canonical}" ]]; then
        ordered+=("${canonical}")
      fi
    done
  done
  printf '%s\n' "${ordered[@]}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  expand_capabilities "$@" || exit $?
fi
