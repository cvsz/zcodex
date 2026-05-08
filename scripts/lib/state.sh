#!/usr/bin/env bash
# Install state tracking for resumable and repair-aware zcodex operations.

: "${ZCODEX_STATE_HOME:=${HOME}/.local/share/zcodex}"
: "${ZCODEX_STATE_DIR:=${ZCODEX_STATE_HOME}/state}"
: "${ZCODEX_INSTALL_ID:=}"

state_init() {
	install -d -m 700 "${ZCODEX_STATE_HOME}" "${ZCODEX_STATE_DIR}"
	if [[ -z "${ZCODEX_INSTALL_ID}" ]]; then
		if [[ -r "${ZCODEX_STATE_DIR}/install_id" ]]; then
			ZCODEX_INSTALL_ID="$(cat "${ZCODEX_STATE_DIR}/install_id")"
		else
			ZCODEX_INSTALL_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
		fi
	fi
	printf '%s\n' "${ZCODEX_INSTALL_ID}" >"${ZCODEX_STATE_DIR}/install_id"
	chmod 600 "${ZCODEX_STATE_DIR}/install_id"
}

state_valid_phase() {
	case "$1" in
	VALIDATE | DOWNLOAD | VERIFY | INSTALL | CONFIGURE | VERIFY_RUNTIME | COMPLETE | FAILED) return 0 ;;
	*) return 1 ;;
	esac
}

state_phase_file() {
	printf '%s/current_phase\n' "${ZCODEX_STATE_DIR}"
}

state_status_file() {
	printf '%s/status\n' "${ZCODEX_STATE_DIR}"
}

state_history_file() {
	printf '%s/history.log\n' "${ZCODEX_STATE_DIR}"
}

state_completed_dir() {
	printf '%s/completed.d\n' "${ZCODEX_STATE_DIR}"
}

state_phase_completed_file() {
	local phase="$1"
	printf '%s/%s\n' "$(state_completed_dir)" "${phase}"
}

state_write_status() {
	local status="$1"
	state_init
	printf '%s\n' "${status}" >"$(state_status_file)"
	chmod 600 "$(state_status_file)"
}

state_status() {
	local status_file
	status_file="$(state_status_file)"
	[[ -r "${status_file}" ]] || return 1
	cat "${status_file}"
}

state_mark() {
	local phase="$1"
	local message="${2:-}"
	local status="${3:-running}"
	local now

	if ! state_valid_phase "${phase}"; then
		log_error "Invalid install phase: ${phase}"
		return 1
	fi

	now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	state_init
	printf '%s\n' "${phase}" >"$(state_phase_file)"
	chmod 600 "$(state_phase_file)"
	state_write_status "${status}"
	printf '%s phase=%s status=%s install_id=%s message=%s\n' "${now}" "${phase}" "${status}" "${ZCODEX_INSTALL_ID}" "${message}" >>"$(state_history_file)"
	chmod 600 "$(state_history_file)"
	log_info "Install phase: ${phase} (${status})${message:+ - ${message}}"
}

state_complete_phase() {
	local phase="$1"
	local now

	if ! state_valid_phase "${phase}"; then
		log_error "Invalid install phase: ${phase}"
		return 1
	fi

	state_init
	install -d -m 700 "$(state_completed_dir)"
	now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	printf '%s\n' "${now}" >"$(state_phase_completed_file "${phase}")"
	chmod 600 "$(state_phase_completed_file "${phase}")"
	printf '%s phase=%s status=completed install_id=%s message=phase-complete\n' "${now}" "${phase}" "${ZCODEX_INSTALL_ID}" >>"$(state_history_file)"
}

state_phase_completed() {
	local phase="$1"
	[[ -r "$(state_phase_completed_file "${phase}")" ]]
}

state_reset_progress() {
	state_init
	rm -rf "$(state_completed_dir)"
	install -d -m 700 "$(state_completed_dir)"
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

state_recovery_summary() {
	local phase status
	phase="$(state_current_phase 2>/dev/null || true)"
	status="$(state_status 2>/dev/null || true)"
	[[ -n "${phase}" ]] || return 1
	printf 'phase=%s status=%s\n' "${phase}" "${status:-unknown}"
}
