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
	copy_if_present "${ZCODEX_MANIFEST_FILE:-${HOME:-/tmp}/.local/share/zcodex/manifest.json}" "${staging}/zcodex-diagnostics"
	copy_if_present "${LOG_FILE:-/tmp/zcodex-install.log}" "${staging}/zcodex-diagnostics"
	bundle="${OUTPUT_DIR}/${BUNDLE_NAME}"
	LC_ALL=C tar --sort=name --format=posix --mtime="@${epoch}" --owner=0 --group=0 --numeric-owner -cf - -C "${staging}" zcodex-diagnostics | gzip -n >"${bundle}"
	sha256sum "${bundle}" >"${bundle}.sha256"
	printf '%s\n' "${bundle}"
}

main "$@"
