#!/usr/bin/env bash
# Install state tracking for resumable and repair-aware zcodex operations.

: "${ZCODEX_STATE_HOME:=${HOME}/.local/share/zcodex}"
: "${ZCODEX_STATE_DIR:=${ZCODEX_STATE_HOME}/state}"
: "${ZCODEX_INSTALL_ID:=}"

state_home_default() {
	printf '%s\n' "${ZCODEX_STATE_HOME}"
}

state_dir_default() {
	printf '%s\n' "${ZCODEX_STATE_DIR}"
}

state_now_utc() {
	if declare -F zcodex_utc_now >/dev/null 2>&1; then
		zcodex_utc_now
	elif [[ -n "${ZCODEX_FIXED_TIMESTAMP:-}" ]]; then
		printf '%s\n' "${ZCODEX_FIXED_TIMESTAMP}"
	else
		date -u +%Y-%m-%dT%H:%M:%SZ
	fi
}

state_install_id_timestamp() {
	if [[ -n "${ZCODEX_FIXED_INSTALL_ID_TIMESTAMP:-}" ]]; then
		printf '%s\n' "${ZCODEX_FIXED_INSTALL_ID_TIMESTAMP}"
	elif [[ -n "${ZCODEX_FIXED_TIMESTAMP:-}" ]]; then
		printf '%s\n' "${ZCODEX_FIXED_TIMESTAMP//[-:]/}" | sed 's/Z$/Z/'
	else
		date -u +%Y%m%dT%H%M%SZ
	fi
}

state_atomic_write() {
	local target="$1"
	local content="$2"
	local target_dir tmp
	target_dir="$(dirname "${target}")"
	install -d -m 700 "${target_dir}"
	tmp="$(mktemp "${target_dir}/.$(basename "${target}").XXXXXX")"
	printf '%s\n' "${content}" >"${tmp}"
	chmod 600 "${tmp}"
	mv -f "${tmp}" "${target}"
}

state_install_id_file() {
	local state_dir="${1:-$(state_dir_default)}"
	printf '%s/install_id\n' "${state_dir}"
}

state_read_or_create_install_id() {
	local state_dir="${1:-$(state_dir_default)}"
	local install_id_file

	install_id_file="$(state_install_id_file "${state_dir}")"
	if [[ -r "${install_id_file}" ]]; then
		cat "${install_id_file}"
	elif [[ -n "${ZCODEX_INSTALL_ID}" ]]; then
		printf '%s\n' "${ZCODEX_INSTALL_ID}"
	else
		printf '%s-%s\n' "$(state_install_id_timestamp)" "$$"
	fi
}

state_init() {
	local state_home="${1:-$(state_home_default)}"
	local state_dir="${2:-$(state_dir_default)}"
	local install_id

	install -d -m 700 "${state_home}" "${state_dir}"
	install_id="$(state_read_or_create_install_id "${state_dir}")"
	ZCODEX_INSTALL_ID="${install_id}"
	state_atomic_write "$(state_install_id_file "${state_dir}")" "${install_id}"
}

state_valid_phase() {
	case "$1" in
	VALIDATE | DOWNLOAD | VERIFY | RUNTIME_AUDIT | INSTALL | CONFIGURE | VERIFY_RUNTIME | COMPLETE | FAILED) return 0 ;;
	*) return 1 ;;
	esac
}

state_phase_file() {
	local state_dir="${1:-$(state_dir_default)}"
	printf '%s/current_phase\n' "${state_dir}"
}

state_status_file() {
	local state_dir="${1:-$(state_dir_default)}"
	printf '%s/status\n' "${state_dir}"
}

state_history_file() {
	local state_dir="${1:-$(state_dir_default)}"
	printf '%s/history.log\n' "${state_dir}"
}

state_completed_dir() {
	local state_dir="${1:-$(state_dir_default)}"
	printf '%s/completed.d\n' "${state_dir}"
}

state_phase_completed_file() {
	local phase="$1"
	local state_dir="${2:-$(state_dir_default)}"
	printf '%s/%s\n' "$(state_completed_dir "${state_dir}")" "${phase}"
}

state_write_status_in() {
	local state_home="$1"
	local state_dir="$2"
	local status="$3"

	state_init "${state_home}" "${state_dir}"
	state_atomic_write "$(state_status_file "${state_dir}")" "${status}"
}

state_write_status() {
	local status="$1"
	state_write_status_in "$(state_home_default)" "$(state_dir_default)" "${status}"
}

state_status_in() {
	local state_dir="$1"
	local status_file

	status_file="$(state_status_file "${state_dir}")"
	[[ -r "${status_file}" ]] || return 1
	cat "${status_file}"
}

state_status() {
	state_status_in "$(state_dir_default)"
}

state_mark_in() {
	local state_home="$1"
	local state_dir="$2"
	local phase="$3"
	local message="${4:-}"
	local status="${5:-running}"
	local now install_id

	if ! state_valid_phase "${phase}"; then
		log_error "Invalid install phase: ${phase}"
		return 1
	fi

	now="$(state_now_utc)"
	state_init "${state_home}" "${state_dir}"
	install_id="$(state_read_or_create_install_id "${state_dir}")"
	state_atomic_write "$(state_phase_file "${state_dir}")" "${phase}"
	state_write_status_in "${state_home}" "${state_dir}" "${status}"
	printf '%s phase=%s status=%s install_id=%s message=%s\n' "${now}" "${phase}" "${status}" "${install_id}" "${message}" >>"$(state_history_file "${state_dir}")"
	chmod 600 "$(state_history_file "${state_dir}")"
	log_info "Install phase: ${phase} (${status})${message:+ - ${message}}"
}

state_mark() {
	local phase="$1"
	local message="${2:-}"
	local status="${3:-running}"
	state_mark_in "$(state_home_default)" "$(state_dir_default)" "${phase}" "${message}" "${status}"
}

state_complete_phase_in() {
	local state_home="$1"
	local state_dir="$2"
	local phase="$3"
	local now install_id

	if ! state_valid_phase "${phase}"; then
		log_error "Invalid install phase: ${phase}"
		return 1
	fi

	state_init "${state_home}" "${state_dir}"
	install -d -m 700 "$(state_completed_dir "${state_dir}")"
	now="$(state_now_utc)"
	install_id="$(state_read_or_create_install_id "${state_dir}")"
	state_atomic_write "$(state_phase_completed_file "${phase}" "${state_dir}")" "${now}"
	printf '%s phase=%s status=completed install_id=%s message=phase-complete\n' "${now}" "${phase}" "${install_id}" >>"$(state_history_file "${state_dir}")"
}

state_complete_phase() {
	local phase="$1"
	state_complete_phase_in "$(state_home_default)" "$(state_dir_default)" "${phase}"
}

state_phase_completed_in() {
	local state_dir="$1"
	local phase="$2"
	[[ -r "$(state_phase_completed_file "${phase}" "${state_dir}")" ]]
}

state_phase_completed() {
	local phase="$1"
	state_phase_completed_in "$(state_dir_default)" "${phase}"
}

state_reset_progress_in() {
	local state_home="$1"
	local state_dir="$2"

	state_init "${state_home}" "${state_dir}"
	rm -rf "$(state_completed_dir "${state_dir}")"
	install -d -m 700 "$(state_completed_dir "${state_dir}")"
}

state_reset_progress() {
	state_reset_progress_in "$(state_home_default)" "$(state_dir_default)"
}

state_current_phase_in() {
	local state_dir="$1"
	local phase_file

	phase_file="$(state_phase_file "${state_dir}")"
	[[ -r "${phase_file}" ]] || return 1
	cat "${phase_file}"
}

state_current_phase() {
	state_current_phase_in "$(state_dir_default)"
}

state_is_incomplete() {
	local phase
	phase="$(state_current_phase 2>/dev/null || true)"
	[[ -n "${phase}" && "${phase}" != "COMPLETE" ]]
}

state_recovery_summary_in() {
	local state_dir="$1"
	local phase status

	phase="$(state_current_phase_in "${state_dir}" 2>/dev/null || true)"
	status="$(state_status_in "${state_dir}" 2>/dev/null || true)"
	[[ -n "${phase}" ]] || return 1
	printf 'phase=%s status=%s\n' "${phase}" "${status:-unknown}"
}

state_recovery_summary() {
	state_recovery_summary_in "$(state_dir_default)"
}
