#!/usr/bin/env bash
# Security primitives for PATH validation, tempfiles, locking, checksums, and downloads.

: "${ZCODEX_TMP_DIR:=}"
: "${ZCODEX_SECURE_PATH:=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}"
: "${ZCODEX_ALLOW_INSECURE_PATH:=false}"

security_path_split() {
	local path_value="$1"
	tr ':' '\n' <<<"${path_value}"
}

security_canonical_path_entry() {
	local entry="$1"
	[[ -n "${entry}" && -d "${entry}" ]] || return 1
	cd "${entry}" 2>/dev/null && pwd -P
}

security_path_entry_is_writable_by_untrusted() {
	local entry="$1"
	local mode owner_uid current_uid

	[[ -d "${entry}" ]] || return 1
	mode="$(stat -Lc '%a' "${entry}" 2>/dev/null || printf '0')"
	owner_uid="$(stat -Lc '%u' "${entry}" 2>/dev/null || printf '-1')"
	current_uid="${EUID}"

	case "${mode: -2:1}${mode: -1}" in
	*[2367]*) return 0 ;;
	esac

	# A user-owned PATH entry is unsafe for root-mediated execution because the
	# user can replace binaries after validation but before a sudo command runs.
	if [[ "${current_uid}" -ne 0 && "${owner_uid}" -eq "${current_uid}" ]]; then
		case "${entry}" in
		/usr/bin | /bin | /usr/sbin | /sbin | /usr/local/bin | /usr/local/sbin) return 1 ;;
		*) return 0 ;;
		esac
	fi
	return 1
}

security_validate_path() {
	local path_value="${1:-${PATH:-}}"
	local entry canonical seen=":" failed=0

	if [[ -z "${path_value}" ]]; then
		log_error 'PATH is empty; refusing non-deterministic command resolution.'
		return 1
	fi
	if [[ "${path_value}" == *::* || "${path_value}" == :* || "${path_value}" == *: ]]; then
		log_error 'PATH contains an empty segment, which resolves to the current directory.'
		failed=1
	fi

	while IFS= read -r entry; do
		[[ -n "${entry}" ]] || continue
		case "${entry}" in
		/*) ;;
		*)
			log_error "PATH entry is not absolute: ${entry}"
			failed=1
			continue
			;;
		esac
		canonical="$(security_canonical_path_entry "${entry}" 2>/dev/null || true)"
		if [[ -z "${canonical}" ]]; then
			log_error "PATH entry is not a readable directory: ${entry}"
			failed=1
			continue
		fi
		if [[ "${seen}" == *":${canonical}:"* ]]; then
			log_warn "Duplicate PATH entry after canonicalization: ${entry} -> ${canonical}"
		fi
		seen+="${canonical}:"
		if security_path_entry_is_writable_by_untrusted "${canonical}"; then
			log_error "PATH entry is writable by an untrusted principal for privileged execution: ${canonical}"
			failed=1
		fi
	done < <(security_path_split "${path_value}")

	((failed == 0))
}

security_canonicalize_path() {
	local path_value="${1:-${PATH:-}}"
	local entry canonical output="" seen=":"
	while IFS= read -r entry; do
		[[ -n "${entry}" ]] || continue
		canonical="$(security_canonical_path_entry "${entry}" 2>/dev/null || true)"
		[[ -n "${canonical}" ]] || continue
		if [[ "${seen}" == *":${canonical}:"* ]]; then
			continue
		fi
		seen+="${canonical}:"
		output+="${output:+:}${canonical}"
	done < <(security_path_split "${path_value}")
	printf '%s\n' "${output}"
}

security_export_canonical_path() {
	local canonical
	security_validate_path "${PATH:-}" || return 1
	canonical="$(security_canonicalize_path "${PATH:-}")"
	[[ -n "${canonical}" ]] || return 1
	export PATH="${canonical}"
}

security_create_tmpdir() {
	local parent
	parent="${TMPDIR:-/tmp}"
	[[ -d "${parent}" ]] || parent=/tmp
	ZCODEX_TMP_DIR="$(mktemp -d "${parent%/}/zcodex.XXXXXXXXXX")"
	chmod 700 "${ZCODEX_TMP_DIR}"
	printf '%s\n' "${ZCODEX_TMP_DIR}"
}

security_cleanup_tmpdir() {
	if [[ -n "${ZCODEX_TMP_DIR}" && -d "${ZCODEX_TMP_DIR}" ]]; then
		case "$(readlink -f "${ZCODEX_TMP_DIR}" 2>/dev/null || true)" in
		/tmp/zcodex.* | /var/tmp/zcodex.* | */zcodex.*) rm -rf "${ZCODEX_TMP_DIR}" ;;
		*) log_warn "Refusing to cleanup suspicious temp directory: ${ZCODEX_TMP_DIR}" ;;
		esac
	fi
}

security_acquire_lock() {
	local lock_file="$1"
	install -d -m 700 "$(dirname "${lock_file}")"
	exec 9>"${lock_file}"
	if ! flock -n 9; then
		log_error "Another zcodex process is already running. Lock: ${lock_file}"
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
	local actual_sha256

	if [[ ! "${expected_sha256}" =~ ^[A-Fa-f0-9]{64}$ ]]; then
		log_error "Invalid SHA-256 digest for ${file}."
		return 1
	fi
	[[ -r "${file}" && -f "${file}" ]] || {
		log_error "Checksum target is not a readable regular file: ${file}"
		return 1
	}
	actual_sha256="$(sha256sum "${file}" | awk '{ print $1 }')"
	if [[ "${actual_sha256}" != "${expected_sha256,,}" ]]; then
		log_error "SHA-256 mismatch for ${file}: expected ${expected_sha256}, got ${actual_sha256}."
		return 1
	fi
}

security_manifest_digest() {
	local manifest="$1"
	local artifact_name="$2"
	local digest

	[[ -r "${manifest}" && -f "${manifest}" ]] || return 1
	digest="$(awk -v artifact="${artifact_name}" 'NF == 2 && $2 == artifact { print $1; found = 1; exit } END { if (!found) exit 1 }' "${manifest}")" || return 1
	[[ "${digest}" =~ ^[A-Fa-f0-9]{64}$ ]] || return 1
	printf '%s\n' "${digest}"
}

security_verify_manifest_entry() {
	local manifest="$1"
	local artifact="$2"
	local artifact_name
	local expected_sha256

	artifact_name="$(basename "${artifact}")"
	expected_sha256="$(security_manifest_digest "${manifest}" "${artifact_name}")" || {
		log_error "No valid checksum entry for ${artifact_name} in ${manifest}."
		return 1
	}
	security_verify_sha256 "${artifact}" "${expected_sha256}"
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

security_download_verified() {
	local url="$1"
	local output="$2"
	local manifest="$3"

	security_download "${url}" "${output}"
	security_verify_manifest_entry "${manifest}" "${output}"
}
