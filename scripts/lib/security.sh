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

security_path_entry_is_user_npm_global() {
	local entry="$1"
	[[ -n "${HOME:-}" ]] || return 1
	case "${entry}" in
	"${HOME}"/.npm-global | "${HOME}"/.npm-global/*) return 0 ;;
	*) return 1 ;;
	esac
}

security_path_entry_is_user_local_safe() {
	local entry="$1"
	[[ -n "${HOME:-}" ]] || return 1
	if [[ "${EUID}" -eq 0 ]]; then
		return 1
	fi
	case "${entry}" in
	"${HOME}"/.local/bin) return 0 ;;
	*) return 1 ;;
	esac
}

security_path_entry_classification() {
	local entry="$1"
	case "${entry}" in
	/usr/bin | /usr/sbin | /bin | /sbin) printf 'TRUSTED_SYSTEM\n' ;;
	*)
		if security_path_entry_is_user_local_safe "${entry}"; then
			printf 'USER_LOCAL_SAFE\n'
		elif security_path_entry_is_user_dotnet "${entry}" || security_path_entry_is_user_npm_global "${entry}" || security_path_entry_is_writable_by_untrusted "${entry}"; then
			printf 'USER_LOCAL_RISKY\n'
		else
			printf 'UNKNOWN\n'
		fi
		;;
	esac
}

security_path_json_escape() {
	if declare -F log_json_escape >/dev/null 2>&1; then
		log_json_escape "$1"
		return 0
	fi
	local value="$1"
	value="${value//\\/\\\\}"
	value="${value//\"/\\\"}"
	value="${value//$'\n'/\\n}"
	value="${value//$'\r'/\\r}"
	value="${value//$'\t'/\\t}"
	printf '%s' "${value}"
}

security_path_analysis_json() {
	local path="$1" classification="$2" risk_score="$3" reason="$4" action="$5"
	printf '{"path":"%s","classification":"%s","risk_score":%s,"reason":"%s","action":"%s"}\n' \
		"$(security_path_json_escape "${path}")" \
		"$(security_path_json_escape "${classification}")" \
		"${risk_score}" \
		"$(security_path_json_escape "${reason}")" \
		"$(security_path_json_escape "${action}")"
}

security_path_score_entry() {
	local classification="$1" writable_executable="$2" before_system="$3"
	local risk_score=0
	if [[ "${classification}" != "TRUSTED_SYSTEM" ]]; then
		risk_score=20
	fi
	case "${classification}" in
	TRUSTED_SYSTEM) ;;
	USER_LOCAL_SAFE) risk_score=$((risk_score + 10)) ;;
	USER_LOCAL_RISKY) risk_score=$((risk_score + 30)) ;;
	UNKNOWN) risk_score=$((risk_score + 60)) ;;
	esac
	if [[ "${writable_executable}" == "true" ]]; then
		risk_score=$((risk_score + 20))
	fi
	if [[ "${before_system}" == "true" ]]; then
		risk_score=$((risk_score + 15))
	fi
	((risk_score > 100)) && risk_score=100
	printf '%s\n' "${risk_score}"
}

security_analyze_path() {
	local path_value="${1:-${PATH:-}}"
	local mode="${2:-strict}"
	local emit_json="${3:-true}"
	local entry canonical classification seen=":" failed=0 seen_system=false
	local writable_executable before_system risk_score action reason

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

		classification="$(security_path_entry_classification "${canonical}")"
		writable_executable=false
		if security_path_entry_is_writable_by_untrusted "${canonical}" && [[ -x "${canonical}" ]]; then
			writable_executable=true
		fi
		before_system=false
		if [[ "${seen_system}" != "true" && "${classification}" != "TRUSTED_SYSTEM" ]]; then
			before_system=true
		fi
		risk_score="$(security_path_score_entry "${classification}" "${writable_executable}" "${before_system}")"
		action=allow
		if ((risk_score >= 85)) && security_path_validation_is_strict "${mode}"; then
			action=block
			failed=1
		elif ((risk_score > 0)); then
			action=warn
		fi

		reason="base risk 0; classification=${classification}"
		if [[ "${classification}" != "TRUSTED_SYSTEM" ]]; then
			reason="base risk 20; classification=${classification}"
		fi
		case "${classification}" in
		USER_LOCAL_SAFE) reason+=' (+10 user-local safe)' ;;
		USER_LOCAL_RISKY) reason+=' (+30 user-local risky)' ;;
		UNKNOWN) reason+=' (+60 unknown)' ;;
		esac
		if [[ "${writable_executable}" == "true" ]]; then
			reason+='; writable executable directory (+20)'
		fi
		if [[ "${before_system}" == "true" ]]; then
			reason+='; appears before trusted system PATH (+15)'
		fi
		if [[ "${action}" == "block" ]]; then
			reason+='; strict mode blocks scores >= 85'
		elif ((risk_score >= 85)); then
			reason+='; strict mode disabled so downgraded to warning'
		fi

		if [[ "${emit_json}" == "true" ]]; then
			security_path_analysis_json "${canonical}" "${classification}" "${risk_score}" "${reason}" "${action}"
		fi
		case "${action}" in
		block) log_error "PATH risk blocked: ${canonical} score=${risk_score} classification=${classification}. ${reason}" ;;
		warn) log_warn "PATH risk warning: ${canonical} score=${risk_score} classification=${classification}. ${reason}" ;;
		esac
		if [[ "${classification}" == "TRUSTED_SYSTEM" ]]; then
			seen_system=true
		fi
	done < <(security_path_split "${path_value}")

	((failed == 0))
}

security_validate_path() {
	security_analyze_path "${1:-${PATH:-}}" "${2:-strict}" false
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
