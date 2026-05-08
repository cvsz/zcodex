#!/usr/bin/env bash
# Small runtime execution and trap helpers.

runtime_command_exists() {
	command -v "$1" >/dev/null 2>&1
}

runtime_exec_logged() {
	local log_file="$1"
	local description="$2"
	shift 2

	printf '[Codex] %s\n' "${description}" | tee -a "${log_file}"
	"$@" 2>&1 | tee -a "${log_file}"
	return "${PIPESTATUS[0]}"
}

runtime_noop() { :; }

runtime_trap_install_exit() {
	local handler="$1"
	local previous

	previous="$(trap -p EXIT || true)"
	if [[ -n "${previous}" ]]; then
		log_warn "Replacing existing EXIT trap with ${handler}; previous trap was: ${previous}"
	fi
	# shellcheck disable=SC2064 # The handler name is intentionally captured at install time.
	trap "${handler}" EXIT
}

runtime_privileged() {
	local sudo_path
	if [[ "${EUID}" -eq 0 ]]; then
		env PATH="${ZCODEX_SECURE_PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}" "$@"
		return $?
	fi
	if ! runtime_command_exists sudo; then
		log_error "sudo is required for privileged command: $*"
		return 1
	fi
	sudo_path="$(command -v sudo)"
	case "${sudo_path}" in
	/usr/bin/sudo | /bin/sudo) ;;
	*)
		log_error "Refusing sudo outside trusted system paths: ${sudo_path}"
		return 1
		;;
	esac
	"${sudo_path}" env PATH="${ZCODEX_SECURE_PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}" "$@"
}
