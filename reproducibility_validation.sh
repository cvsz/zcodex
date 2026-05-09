#!/usr/bin/env bash
# Validate that zcodex release archives rebuild byte-for-byte.

set -Eeuo pipefail

export LC_ALL=C.UTF-8
export LANG=C.UTF-8
export TZ=UTC
umask 022

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION_FILE="${SCRIPT_DIR}/VERSION"
OUT_A="${OUT_A:-${SCRIPT_DIR}/dist.repro-a}"
OUT_B="${OUT_B:-${SCRIPT_DIR}/dist.repro-b}"

fail() {
	printf '[repro] ERROR: %s\n' "$*" >&2
	exit 1
}

require_command() {
	command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

main() {
	require_command bash
	require_command cmp
	require_command sha256sum
	[[ -f "${VERSION_FILE}" ]] || fail "missing VERSION file"

	local version archive_a archive_b sha_a sha_b
	version="$(tr -d '[:space:]' <"${VERSION_FILE}")"
	archive_a="${OUT_A}/zcodex-v${version}.tar.gz"
	archive_b="${OUT_B}/zcodex-v${version}.tar.gz"

	rm -rf "${OUT_A}" "${OUT_B}"
	bash "${SCRIPT_DIR}/scripts/build-release.sh" --output-dir "${OUT_A}"
	bash "${SCRIPT_DIR}/scripts/build-release.sh" --output-dir "${OUT_B}"

	(
		cd "${OUT_A}"
		sha256sum -c SHA256SUMS
	)
	(
		cd "${OUT_B}"
		sha256sum -c SHA256SUMS
	)
	cmp "${archive_a}" "${archive_b}"

	sha_a="$(sha256sum "${archive_a}" | awk '{ print $1 }')"
	sha_b="$(sha256sum "${archive_b}" | awk '{ print $1 }')"
	[[ "${sha_a}" == "${sha_b}" ]] || fail "checksum mismatch: ${sha_a} != ${sha_b}"
	printf '[repro] OK: %s  zcodex-v%s.tar.gz\n' "${sha_a}" "${version}"
}

main "$@"
