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
				return 2
			fi
			case "$1" in
			clean-system | existing-runtime | ci | developer | production) ZCODEX_RUNTIME_MODE="$1" ;;
			*)
				log_error "Invalid runtime mode: $1"
				return 2
				;;
			esac
			;;
		--dry-run) DRY_RUN=true ;;
		--skip-docker) SKIP_DOCKER=true ;;
		--skip-optional) SKIP_OPTIONAL=true ;;
		-h | --help)
			installer_usage
			return 64
			;;
		*)
			log_error "Unknown option: $1"
			installer_usage
			return 2
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
	shift 2

	if installer_phase_can_resume "${phase}" && state_phase_completed "${phase}"; then
		runtime_ctx_set phase "${phase}"
		runtime_ctx_set phase_status skipped
		log_success "Skipping ${phase}; completed in previous interrupted run."
		return 0
	fi

	runtime_ctx_set phase "${phase}"
	runtime_ctx_set phase_message "${message}"
	runtime_ctx_set phase_status running
	state_mark "${phase}" "${message}" running
	"$@"
	runtime_ctx_set phase_status completed
	state_complete_phase "${phase}"
	manifest_write running
}

installer_prepare_recovery() {
	if [[ -n "${INSTALLER_PREVIOUS_PHASE}" && "${INSTALLER_PREVIOUS_PHASE}" != "COMPLETE" ]]; then
		log_warn "Interrupted zcodex install detected: $(state_recovery_summary 2>/dev/null || printf 'phase=%s' "${INSTALLER_PREVIOUS_PHASE}")"
		log_warn "Resuming with completed phase markers from ${ZCODEX_STATE_DIR}/completed.d."
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
		64) return 0 ;;
		*) return "${parse_status}" ;;
		esac
	}
	log_section "zcodex installer"

	installer_prepare_command_path
	platform_validate
	pins_validate
	installer_planned_steps

	if [[ "${DRY_RUN}" == "true" ]]; then
		installer_verify_inputs
		installer_runtime_audit_dry_run
		log_success "Dry run completed without making changes."
		return 0
	fi

	INSTALLER_PREVIOUS_PHASE="$(state_current_phase 2>/dev/null || true)"
	INSTALLER_STATE_STARTED=true
	installer_prepare_recovery
	installer_run_phase VALIDATE "validate platform" platform_validate
	installer_run_phase DOWNLOAD "prepare runtime workspace" installer_prepare_runtime
	installer_run_phase VERIFY "validate pins and interrupted state" installer_verify_inputs
	installer_run_phase RUNTIME_AUDIT "audit nodejs and npm ownership" installer_runtime_audit
	installer_run_phase INSTALL "install core runtime" installer_install_all
	installer_run_phase CONFIGURE "configure codex runtime" installer_configure_codex
	installer_run_phase VERIFY_RUNTIME "validate installed tools" installer_verify_runtime
}
