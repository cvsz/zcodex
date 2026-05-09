#!/usr/bin/env bash
set -euo pipefail

runs="${1:-5}"
if ! [[ "$runs" =~ ^[0-9]+$ ]] || (( runs < 1 )); then
  echo "usage: $0 [runs>=1]" >&2
  exit 2
fi

benchmark_case() {
  local label="$1"
  shift
  local total_ms=0
  local elapsed
  for ((i=1; i<=runs; i++)); do
    TIMEFORMAT='%3R'
    elapsed=$( { time "$@" >/dev/null 2>&1; } 2>&1 )
    elapsed="${elapsed/.}"
    total_ms=$((total_ms + elapsed))
  done
  local avg_ms=$((total_ms / runs))
  printf '%s avg=%dms runs=%d\n' "$label" "$avg_ms" "$runs"
}

benchmark_case "installer_dry_run_ci" ./scripts/install-codex-ubuntu.sh --dry-run --ci
