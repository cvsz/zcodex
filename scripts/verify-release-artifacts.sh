#!/usr/bin/env bash
# Verify release artifact checksum manifests and reproducible hashes.

set -Eeuo pipefail

export LC_ALL=C.UTF-8
export LANG=C.UTF-8
export TZ=UTC
umask 022

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DIST_DIR="${1:-${REPO_ROOT}/dist}"

fail() {
	printf '[release-verify] ERROR: %s\n' "$*" >&2
	exit 1
}

main() {
	local sums archive_count
	[[ -d "${DIST_DIR}" ]] || fail "missing artifact directory: ${DIST_DIR}"
	sums="${DIST_DIR}/SHA256SUMS"
	[[ -r "${sums}" && -f "${sums}" ]] || fail "missing checksum manifest: ${sums}"
	archive_count="$(find "${DIST_DIR}" -maxdepth 1 -type f -name 'zcodex-v*.tar.gz' | wc -l | tr -d ' ')"
	[[ "${archive_count}" -eq 1 ]] || fail "expected exactly one release archive, found ${archive_count}"
	(
		cd "${DIST_DIR}"
		sha256sum -c SHA256SUMS
	) || fail "checksum verification failed for ${sums}"
	awk 'NF != 2 || $1 !~ /^[0-9a-f]{64}$/ { bad=1 } END { exit bad }' "${sums}" || fail "checksum manifest must contain '<sha256> <artifact>' entries"
	printf '[release-verify] OK: verified %s\n' "${sums}"
}

main "$@"
