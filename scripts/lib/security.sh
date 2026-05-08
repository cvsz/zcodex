#!/usr/bin/env bash
# Security primitives for tempfiles, locking, checksums, and downloads.

: "${ZCODEX_TMP_DIR:=}"

security_create_tmpdir() {
	ZCODEX_TMP_DIR="$(mktemp -d)"
	chmod 700 "${ZCODEX_TMP_DIR}"
	printf '%s\n' "${ZCODEX_TMP_DIR}"
}

security_cleanup_tmpdir() {
	if [[ -n "${ZCODEX_TMP_DIR}" && -d "${ZCODEX_TMP_DIR}" ]]; then
		rm -rf "${ZCODEX_TMP_DIR}"
	fi
}

security_acquire_lock() {
	local lock_file="$1"
	exec 9>"${lock_file}"
	if ! flock -n 9; then
		log_error "Another zcodex process is already running."
		return 1
	fi
	printf '%s\n' "$$" 1>&9
}

security_release_lock() {
	flock -u 9 2>/dev/null || true
}

security_verify_sha256() {
	local file="$1"
	local expected_sha256="$2"
	printf '%s  %s\n' "${expected_sha256}" "${file}" | sha256sum --check --status
}

security_download() {
	local url="$1"
	local output="$2"
	local expected_sha256="${3:-}"

	if [[ "${url}" != https://* ]]; then
		log_error "Refusing non-HTTPS download: ${url}"
		return 1
	fi

	retry 3 2 curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 --output "${output}" "${url}"
	chmod 600 "${output}"

	if [[ -n "${expected_sha256}" ]]; then
		security_verify_sha256 "${output}" "${expected_sha256}"
	fi
}
