#!/usr/bin/env bash
# Deterministic diagnostics and failure bundle generation.

set -Eeuo pipefail

export LC_ALL=C.UTF-8
export LANG=C.UTF-8
export TZ=UTC
umask 022

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-${REPO_ROOT}/diagnostics}"
BUNDLE_NAME="zcodex-diagnostics.tar.gz"

json_escape() {
	local value="$1"
	value="${value//\\/\\\\}"
	value="${value//\"/\\\"}"
	value="${value//$'\n'/\\n}"
	value="${value//$'\r'/\\r}"
	value="${value//$'\t'/\\t}"
	printf '%s' "${value}"
}

command_version() {
	local name="$1"
	shift
	if command -v "${name}" >/dev/null 2>&1; then
		"${name}" "$@" 2>/dev/null | head -n 1
	else
		printf 'missing'
	fi
}

write_snapshot() {
	local dir="$1"
	local arch kernel path_digest
	arch="$(uname -m 2>/dev/null || printf unknown)"
	kernel="$(uname -sr 2>/dev/null || printf unknown)"
	path_digest="$(printf '%s' "${PATH:-}" | sha256sum | awk '{ print $1 }')"
	cat >"${dir}/runtime-snapshot.json" <<JSON
{
  "schema_version": 1,
  "environment": {
    "lang": "$(json_escape "${LANG:-}")",
    "lc_all": "$(json_escape "${LC_ALL:-}")",
    "tz": "$(json_escape "${TZ:-}")",
    "path_sha256": "${path_digest}"
  },
  "platform": {
    "arch": "$(json_escape "${arch}")",
    "kernel": "$(json_escape "${kernel}")"
  },
  "commands": {
    "bash": "$(json_escape "$(command_version bash --version)")",
    "git": "$(json_escape "$(command_version git --version)")",
    "node": "$(json_escape "$(command_version node --version)")",
    "npm": "$(json_escape "$(command_version npm --version)")",
    "docker": "$(json_escape "$(command_version docker --version)")",
    "codex": "$(json_escape "$(command_version codex --version)")"
  }
}
JSON
}

write_manifest_snapshot() {
	local manifest="$1"
	local dir="$2"
	if [[ -r "${manifest}" && -f "${manifest}" ]] && command -v python3 >/dev/null 2>&1; then
		python3 - "${manifest}" "${dir}/manifest-snapshot.json" <<'PYMANIFEST'
import json
import sys

source, target = sys.argv[1], sys.argv[2]
with open(source, encoding="utf-8") as fh:
    doc = json.load(fh)
with open(target, "w", encoding="utf-8") as fh:
    fh.write(json.dumps(doc, sort_keys=True, indent=2, separators=(",", ": ")) + "\n")
PYMANIFEST
	fi
}

write_state_snapshot() {
	local dir="$1"
	local state_dir="${ZCODEX_STATE_DIR:-${HOME:-/tmp}/.local/share/zcodex/state}"
	local phase status history_digest
	phase="unknown"
	status="unknown"
	history_digest="absent"
	[[ -r "${state_dir}/current_phase" ]] && phase="$(cat "${state_dir}/current_phase")"
	[[ -r "${state_dir}/status" ]] && status="$(cat "${state_dir}/status")"
	[[ -r "${state_dir}/history.log" ]] && history_digest="$(sha256sum "${state_dir}/history.log" | awk '{ print $1 }')"
	cat >"${dir}/state-snapshot.json" <<JSON
{
  "schema_version": 1,
  "state_dir_sha256": "$(printf '%s' "${state_dir}" | sha256sum | awk '{ print $1 }')",
  "phase": "$(json_escape "${phase}")",
  "status": "$(json_escape "${status}")",
  "history_sha256": "${history_digest}"
}
JSON
}

copy_if_present() {
	local source="$1"
	local dest_dir="$2"
	[[ -r "${source}" && -f "${source}" ]] || return 0
	cp "${source}" "${dest_dir}/$(basename "${source}")"
}

main() {
	local staging epoch bundle
	epoch="${SOURCE_DATE_EPOCH:-0}"
	mkdir -p "${OUTPUT_DIR}"
	staging="$(mktemp -d "${TMPDIR:-/tmp}/zcodex-diagnostics.XXXXXX")"
	trap 'rm -rf "'"${staging}"'"' EXIT
	mkdir -p "${staging}/zcodex-diagnostics"
	write_snapshot "${staging}/zcodex-diagnostics"
	write_state_snapshot "${staging}/zcodex-diagnostics"
	write_manifest_snapshot "${ZCODEX_MANIFEST_FILE:-${HOME:-/tmp}/.local/share/zcodex/manifest.json}" "${staging}/zcodex-diagnostics"
	copy_if_present "${ZCODEX_MANIFEST_FILE:-${HOME:-/tmp}/.local/share/zcodex/manifest.json}" "${staging}/zcodex-diagnostics"
	copy_if_present "${LOG_FILE:-/tmp/zcodex-install.log}" "${staging}/zcodex-diagnostics"
	bundle="${OUTPUT_DIR}/${BUNDLE_NAME}"
	LC_ALL=C tar --sort=name --format=posix --mtime="@${epoch}" --owner=0 --group=0 --numeric-owner -cf - -C "${staging}" zcodex-diagnostics | gzip -n >"${bundle}"
	sha256sum "${bundle}" >"${bundle}.sha256"
	printf '%s\n' "${bundle}"
}

main "$@"
