#!/usr/bin/env bash
# Installer orchestration helpers for the zcodex Ubuntu bootstrapper.

: "${SCRIPT_NAME:=$(basename "$0")}"
: "${CI_MODE:=${CI:-false}}"
: "${SKIP_DOCKER:=false}"
: "${SKIP_OPTIONAL:=false}"
: "${DRY_RUN:=false}"
: "${LOCK_FILE:=/tmp/zcodex-install.lock}"
: "${LOG_FILE:=/tmp/zcodex-install.log}"
: "${INSTALLER_PREVIOUS_PHASE:=}"
: "${INSTALLER_STATE_STARTED:=false}"
: "${ZCODEX_ROLLBACK_ON_FAILURE:=true}"
: "${ZCODEX_RUNTIME_MODE:=clean-system}"
: "${ZCODEX_CI_TRUSTED_PATH:=/usr/sbin:/usr/bin:/sbin:/bin}"
readonly ZCODEX_INSTALLER_ERR_INVALID_ARGS=2
readonly ZCODEX_INSTALLER_ERR_INVALID_STATE=3
readonly ZCODEX_INSTALLER_USAGE_EXIT=64

installer_usage() {
	cat <<USAGE
Usage: ${SCRIPT_NAME} [OPTIONS]

Options:
  --ci              Non-interactive CI mode; skips shell profile changes and uses runtime mode ci.
  --runtime-mode MODE
                    Runtime ownership policy: clean-system, existing-runtime, ci, developer, or production.
  --dry-run         Validate runtime capabilities and print the planned install flow.
  --skip-docker     Skip Docker installation and group configuration.
  --skip-optional   Skip optional npm packages.
  -h, --help        Show this help message.
USAGE
}

installer_parse_args() {
	while (($#)); do
		case "$1" in
		--ci)
			CI_MODE=true
			ZCODEX_RUNTIME_MODE=ci
			;;
		--runtime-mode)
			shift
			if [[ -z "${1:-}" ]]; then
				log_error "--runtime-mode requires one of: clean-system, existing-runtime, ci, developer"
				return "${ZCODEX_INSTALLER_ERR_INVALID_ARGS}"
			fi
			case "$1" in
			clean-system | existing-runtime | ci | developer | production) ZCODEX_RUNTIME_MODE="$1" ;;
			*)
				log_error "Invalid runtime mode: $1"
				return "${ZCODEX_INSTALLER_ERR_INVALID_ARGS}"
				;;
			esac
			;;
		--dry-run) DRY_RUN=true ;;
		--skip-docker) SKIP_DOCKER=true ;;
		--skip-optional) SKIP_OPTIONAL=true ;;
		-h | --help)
			installer_usage
			return "${ZCODEX_INSTALLER_USAGE_EXIT}"
			;;
		*)
			log_error "Unknown option: $1"
			installer_usage
			return "${ZCODEX_INSTALLER_ERR_INVALID_ARGS}"
			;;
		esac
		shift
	done
}

installer_planned_steps() {
	cat <<PLAN
Install flow:
  1. VALIDATE runtime capabilities, version pins, CPU architecture, WSL status, container context, and Node.js/npm ownership.
  2. DOWNLOAD package metadata and acquire a process lock, secure workspace, and backup directory.
  3. AUDIT Node.js/npm ownership, PATH shadows, nvm/asdf presence, apt/NodeSource packages, and npm ownership.
  4. INSTALL base packages, pinned Node.js, pinned Codex CLI, and optional Docker.
  5. CONFIGURE Codex config and shell integration.
  6. VERIFY_RUNTIME and write ${ZCODEX_MANIFEST_FILE}.
  7. COMPLETE with explicit state in ${ZCODEX_STATE_DIR}.
PLAN
	pins_summary
	cat <<MODE
Runtime policy:
  mode=${ZCODEX_RUNTIME_MODE}
  user-runtime-mutation=${ZCODEX_ALLOW_USER_RUNTIME_MUTATION}
MODE
}

installer_prepare_command_path() {
	if [[ "${CI_MODE}" == "true" && "${ZCODEX_ALLOW_INSECURE_PATH:-false}" != "true" ]]; then
		log_warn "CI mode detected; replacing PATH with trusted system directories before validation."
		export PATH="${ZCODEX_CI_TRUSTED_PATH}"
	fi

	if [[ "${ZCODEX_ALLOW_INSECURE_PATH:-false}" != "true" ]]; then
		security_export_canonical_path
	else
		log_warn "Skipping strict PATH validation because ZCODEX_ALLOW_INSECURE_PATH=true."
	fi
}

installer_cleanup() {
	local exit_code=$?
	if [[ "${DRY_RUN}" != "true" && "${INSTALLER_STATE_STARTED}" == "true" ]]; then
		if ((exit_code == 0)); then
			runtime_ctx_set phase COMPLETE || true
			runtime_ctx_set phase_status complete || true
			state_mark COMPLETE "installer completed" complete || true
			state_complete_phase COMPLETE || true
			manifest_write complete || true
		else
			runtime_ctx_set phase FAILED || true
			runtime_ctx_set phase_status failed || true
			state_mark FAILED "exit_code=${exit_code}" failed || true
			manifest_write failed || true
			if [[ "${ZCODEX_ROLLBACK_ON_FAILURE}" == "true" ]]; then
				backup_restore_all || true
			fi
		fi
	fi
	security_release_lock
	security_cleanup_tmpdir
	if ((exit_code == 0)); then
		log_success "zcodex installer completed."
	else
		log_error "zcodex installer failed with exit code ${exit_code}. See ${LOG_FILE}."
	fi
	exit "${exit_code}"
}

installer_phase_can_resume() {
	case "$1" in
	INSTALL | CONFIGURE) return 0 ;;
	*) return 1 ;;
	esac
}

installer_run_phase() {
	local phase="$1"
	local message="$2"
	local phase_started_at phase_completed_at phase_elapsed_ms
	shift 2

	if installer_phase_can_resume "${phase}" && state_phase_completed "${phase}"; then
		runtime_ctx_set phase "${phase}"
		runtime_ctx_set phase_status skipped
		log_success "Skipping ${phase}; completed in previous interrupted run."
		return 0
	fi

	phase_started_at="$(date +%s%3N)"
	runtime_ctx_set phase "${phase}"
	runtime_ctx_set phase_message "${message}"
	runtime_ctx_set phase_status running
	state_mark "${phase}" "${message}" running
	"$@"
	phase_completed_at="$(date +%s%3N)"
	phase_elapsed_ms="$((phase_completed_at - phase_started_at))"
	runtime_ctx_set phase_elapsed_ms "${phase_elapsed_ms}"
	runtime_ctx_set phase_status completed
	log_info "Phase timing: ${phase} duration_ms=${phase_elapsed_ms}"
	state_complete_phase "${phase}"
	manifest_write running
}

installer_phase_handler() {
	case "$1" in
	VALIDATE) printf '%s\n' "platform_validate" ;;
	DOWNLOAD) printf '%s\n' "installer_prepare_runtime" ;;
	VERIFY) printf '%s\n' "installer_verify_inputs" ;;
	RUNTIME_AUDIT) printf '%s\n' "installer_runtime_audit" ;;
	INSTALL) printf '%s\n' "installer_install_all" ;;
	CONFIGURE) printf '%s\n' "installer_configure_codex" ;;
	VERIFY_RUNTIME) printf '%s\n' "installer_verify_runtime" ;;
	*)
		log_error "Unknown installer phase '${1}'"
		return "${ZCODEX_INSTALLER_ERR_INVALID_STATE}"
		;;
	esac
}

installer_phase_message() {
	case "$1" in
	VALIDATE) printf '%s\n' "validate platform" ;;
	DOWNLOAD) printf '%s\n' "prepare runtime workspace" ;;
	VERIFY) printf '%s\n' "validate pins and interrupted state" ;;
	RUNTIME_AUDIT) printf '%s\n' "audit nodejs and npm ownership" ;;
	INSTALL) printf '%s\n' "install core runtime" ;;
	CONFIGURE) printf '%s\n' "configure codex runtime" ;;
	VERIFY_RUNTIME) printf '%s\n' "validate installed tools" ;;
	*)
		log_error "Unknown installer phase '${1}'"
		return "${ZCODEX_INSTALLER_ERR_INVALID_STATE}"
		;;
	esac
}

installer_run_default_phases() {
	local phase handler message
	local -a phases=(VALIDATE DOWNLOAD VERIFY RUNTIME_AUDIT INSTALL CONFIGURE VERIFY_RUNTIME)
	for phase in "${phases[@]}"; do
		handler="$(installer_phase_handler "${phase}")" || return $?
		message="$(installer_phase_message "${phase}")" || return $?
		installer_run_phase "${phase}" "${message}" "${handler}"
	done
}

installer_prepare_recovery() {
	if [[ -n "${INSTALLER_PREVIOUS_PHASE}" && "${INSTALLER_PREVIOUS_PHASE}" != "COMPLETE" ]]; then
		log_warn "Interrupted zcodex install detected: $(state_recovery_summary 2>/dev/null || printf 'phase=%s' "${INSTALLER_PREVIOUS_PHASE}")"
		state_reconcile >/dev/null || return 1
		log_warn "Resuming with reconciled completed phase markers from ${ZCODEX_STATE_DIR}/completed.d."
		return 0
	fi

	state_reset_progress
}

installer_prepare_runtime() {
	security_acquire_lock "${LOCK_FILE}"
	security_create_tmpdir >/dev/null
	backup_init >/dev/null
}

installer_verify_inputs() {
	if [[ -n "${INSTALLER_PREVIOUS_PHASE}" && "${INSTALLER_PREVIOUS_PHASE}" != "COMPLETE" ]]; then
		log_warn "Previous install state was incomplete at phase ${INSTALLER_PREVIOUS_PHASE}. Continuing deterministically."
	fi
	pins_validate
	case "${ZCODEX_RUNTIME_MODE}" in
	clean-system | existing-runtime | ci | developer | production) ;;
	*)
		log_error "Invalid runtime mode: ${ZCODEX_RUNTIME_MODE}"
		return 1
		;;
	esac
}

installer_runtime_audit() {
	nodejs_runtime_audit_phase true
}

installer_runtime_audit_dry_run() {
	nodejs_runtime_audit_phase false
}

installer_install_core() {
	packages_update
	packages_install_base
	nodejs_install_managed
	codex_install_cli
}

installer_install_optional_packages() {
	if [[ "${SKIP_OPTIONAL}" == "true" ]]; then
		log_info "Skipping optional npm packages."
		return 0
	fi

	nodejs_install_global_packages npm-check-updates
}

installer_install_docker() {
	if [[ "${SKIP_DOCKER}" == "true" ]]; then
		log_info "Skipping Docker installation."
		return 0
	fi

	docker_install_managed
	docker_configure_user
}

installer_install_all() {
	installer_install_core
	installer_install_optional_packages
	installer_install_docker
}

installer_configure_codex() {
	codex_write_config
	shell_configure_codex
}

installer_verify_runtime() {
	codex_validate_cli || log_warn "Codex CLI validation did not pass in this environment."
}

installer_run() {
	local parse_status

	logging_init
	installer_parse_args "$@" || {
		parse_status="$?"
		case "${parse_status}" in
		"${ZCODEX_INSTALLER_USAGE_EXIT}") return 0 ;;
		*) return "${parse_status}" ;;
		esac
	}
	log_section "zcodex installer"

	installer_prepare_command_path
	installer_planned_steps

	if [[ "${DRY_RUN}" == "true" ]]; then
		installer_verify_inputs
		platform_validate
		installer_runtime_audit_dry_run
		log_success "Dry run completed without making changes."
		return 0
	fi

	INSTALLER_PREVIOUS_PHASE="$(state_current_phase 2>/dev/null || true)"
	INSTALLER_STATE_STARTED=true
	installer_prepare_recovery
	installer_run_default_phases
}
