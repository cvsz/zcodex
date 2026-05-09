#!/usr/bin/env bash
set -Eeuo pipefail

# Extracts a bounded, normalized CI failure context block from a raw job log.
# This keeps Prompt A input compact and deterministic for API consumption.

usage() {
  cat <<'USAGE' >&2
Usage: scripts/extract-failure-context.sh <log_file> [max_lines]
USAGE
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage
  exit 64
fi

log_file="$1"
max_lines="${2:-250}"

if [[ ! -f "$log_file" ]]; then
  printf 'log file not found: %s\n' "$log_file" >&2
  exit 66
fi

if ! [[ "$max_lines" =~ ^[0-9]+$ ]] || [[ "$max_lines" -lt 1 ]]; then
  printf 'max_lines must be a positive integer: %s\n' "$max_lines" >&2
  exit 64
fi

sanitized="$(mktemp)"
trap 'rm -f "$sanitized"' EXIT

# Remove ANSI escapes and CRLF so downstream tokenization is stable.
sed -E 's/\x1B\[[0-9;]*[A-Za-z]//g' "$log_file" | tr -d '\r' >"$sanitized"

# Prioritize the tail from first explicit failure marker, else use the log tail.
start_line="$(grep -nE '(^|\s)(ERROR|Error|FAILED|Failure|Permission denied|No such file|Traceback|exit code)' "$sanitized" | head -n1 | cut -d: -f1 || true)"

if [[ -n "$start_line" ]]; then
  tail -n "+$start_line" "$sanitized" | tail -n "$max_lines"
else
  tail -n "$max_lines" "$sanitized"
fi
