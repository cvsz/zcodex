#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

failures=0

check_pair() {
  local manifest="$1"
  local lockfile="$2"
  if [[ -f "$manifest" ]]; then
    if [[ ! -f "$lockfile" ]]; then
      echo "missing lockfile: $lockfile (required by $manifest)" >&2
      failures=1
    fi
  fi
}

check_pair "package.json" "package-lock.json"
check_pair "pnpm-workspace.yaml" "pnpm-lock.yaml"
check_pair "pyproject.toml" "poetry.lock"
check_pair "Cargo.toml" "Cargo.lock"
check_pair "go.mod" "go.sum"

if [[ -f "requirements.txt" ]] && ! rg -q -- '^[[:space:]]*[^#[:space:]].*==[^[:space:]]+' requirements.txt; then
  echo "requirements.txt must pin exact versions with ==" >&2
  failures=1
fi

if [[ "$failures" -ne 0 ]]; then
  exit 1
fi

echo "Lockfile policy check passed."
