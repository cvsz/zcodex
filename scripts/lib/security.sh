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

	case "${entry}" in
	/bin)
		if [[ -d /usr/bin ]]; then
			printf '%s\n' /usr/bin
			return 0
		fi
		;;
	/sbin)
		if [[ -d /usr/sbin ]]; then
			printf '%s\n' /usr/sbin
			return 0
		fi
		;;
	esac

	if command -v readlink >/dev/null 2>&1; then
		readlink -f "${entry}" 2>/dev/null && return 0
	fi

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

	# User-owned PATH entries are unsafe for privileged execution because that
	# user can replace binaries after validation but before a privileged command
	# runs. When already running as root, any non-root-owned PATH entry is outside
	# the trusted root/system boundary.
	if [[ "${current_uid}" -ne 0 && "${owner_uid}" -eq "${current_uid}" ]]; then
		case "${entry}" in
		/usr/bin | /bin | /usr/sbin | /sbin | /usr/local/bin | /usr/local/sbin) return 1 ;;
		*) return 0 ;;
		esac
	fi
	if [[ "${current_uid}" -eq 0 && "${owner_uid}" -ne 0 ]]; then
		case "${entry}" in
		/usr/bin | /bin | /usr/sbin | /sbin | /usr/local/bin | /usr/local/sbin) return 1 ;;
		*) return 0 ;;
		esac
	fi
	return 1
}

security_path_validation_is_strict() {
	local mode="${1:-strict}"
	case "${mode}" in
	strict | privileged | install | 1 | true | TRUE | yes | YES | on | ON) return 0 ;;
	*) return 1 ;;
	esac
}

security_path_entry_is_safe_prefix() {
	local entry="$1"
	case "${entry}" in
	/usr/bin | /usr/bin/* | /usr/sbin | /usr/sbin/* | /usr/local/bin | /usr/local/bin/* | /usr/local/sbin | /usr/local/sbin/*) return 0 ;;
	/bin | /bin/* | /sbin | /sbin/*) return 0 ;;
	*) return 1 ;;
	esac
}

security_path_entry_is_user_dotnet() {
	local entry="$1"
	[[ -n "${HOME:-}" ]] || return 1
	case "${entry}" in
	"${HOME}"/.dotnet | "${HOME}"/.dotnet/*) return 0 ;;
	*) return 1 ;;
	esac
}

security_validate_path() {
	local path_value="${1:-${PATH:-}}"
	local mode="${2:-strict}"
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

		if security_path_entry_is_safe_prefix "${canonical}"; then
			continue
		fi

		if security_path_entry_is_writable_by_untrusted "${canonical}"; then
			if ! security_path_validation_is_strict "${mode}"; then
				log_warn "User-writable PATH entry detected in non-privileged validation: ${canonical}"
				continue
			fi

			if security_path_entry_is_user_dotnet "${canonical}"; then
				log_warn "User-local .dotnet PATH entry detected during privileged validation; ensure it does not shadow system binaries: ${canonical}"
				continue
			fi

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
	security_validate_path "${PATH:-}" strict || return 1
	canonical="$(security_canonicalize_path "${PATH:-}")"
	[[ -n "${canonical}" ]] || return 1
	export PATH="${canonical}"
}

security_create_tmpdir() {
	local parent
	parent="${TMPDIR:-/tmp}"
	[[ -d "${parent}" ]] || parent=/tmp
	security_validate_tmp_parent "${parent}" || parent=/tmp
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

security_command_trusted_path() {
	local command_name="$1"
	local command_path
	command_path="$(command -v "${command_name}" 2>/dev/null || true)"
	[[ -n "${command_path}" ]] || return 1
	case "${command_path}" in
	/usr/bin/* | /bin/* | /usr/sbin/* | /sbin/* | /usr/local/bin/* | /usr/local/sbin/*) return 0 ;;
	*) return 1 ;;
	esac
}

security_detect_path_shadowing() {
	local failed=0 command_name command_path
	for command_name in "$@"; do
		command_path="$(command -v "${command_name}" 2>/dev/null || true)"
		[[ -n "${command_path}" ]] || continue
		if ! security_command_trusted_path "${command_name}"; then
			log_error "Command ${command_name} resolves outside trusted PATH boundary: ${command_path}"
			failed=1
		fi
	done
	((failed == 0))
}

security_validate_tmp_parent() {
	local parent="${1:-${TMPDIR:-/tmp}}"
	local mode
	[[ -d "${parent}" ]] || return 1
	mode="$(stat -Lc '%a' "${parent}" 2>/dev/null || printf '0')"
	case "${mode: -1}" in
	2 | 3 | 6 | 7)
		case "${mode}" in
		*1?? | *[0-9]1[0-9] | *[0-9][0-9]1) return 0 ;;
		*)
			log_error "Temporary directory ${parent} is world-writable without sticky bit."
			return 1
			;;
		esac
		;;
	esac
}
