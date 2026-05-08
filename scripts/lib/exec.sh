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
