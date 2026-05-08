#!/usr/bin/env bash
# Install state tracking for resumable and repair-aware zcodex operations.

: "${ZCODEX_STATE_HOME:=${HOME}/.local/share/zcodex}"
: "${ZCODEX_STATE_DIR:=${ZCODEX_STATE_HOME}/state}"
: "${ZCODEX_INSTALL_ID:=}"

state_init() {
	install -d -m 700 "${ZCODEX_STATE_HOME}" "${ZCODEX_STATE_DIR}"
	if [[ -z "${ZCODEX_INSTALL_ID}" ]]; then
		ZCODEX_INSTALL_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
	fi
	printf '%s\n' "${ZCODEX_INSTALL_ID}" >"${ZCODEX_STATE_DIR}/install_id"
	chmod 600 "${ZCODEX_STATE_DIR}/install_id"
}

state_phase_file() {
	printf '%s/current_phase\n' "${ZCODEX_STATE_DIR}"
}

state_history_file() {
	printf '%s/history.log\n' "${ZCODEX_STATE_DIR}"
}

state_mark() {
	local phase="$1"
	local message="${2:-}"
	local now
	now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

	state_init
	printf '%s\n' "${phase}" >"$(state_phase_file)"
	chmod 600 "$(state_phase_file)"
	printf '%s phase=%s install_id=%s message=%s\n' "${now}" "${phase}" "${ZCODEX_INSTALL_ID}" "${message}" >>"$(state_history_file)"
	chmod 600 "$(state_history_file)"
	log_info "Install phase: ${phase}${message:+ - ${message}}"
}

state_current_phase() {
	local phase_file
	phase_file="$(state_phase_file)"
	[[ -r "${phase_file}" ]] || return 1
	cat "${phase_file}"
}

state_is_incomplete() {
	local phase
	phase="$(state_current_phase 2>/dev/null || true)"
	[[ -n "${phase}" && "${phase}" != "COMPLETE" ]]
}
