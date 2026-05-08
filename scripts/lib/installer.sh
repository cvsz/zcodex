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

installer_usage() {
	cat <<USAGE
Usage: ${SCRIPT_NAME} [OPTIONS]

Options:
  --ci              Non-interactive CI mode; skips shell profile changes.
  --dry-run         Validate platform and print the planned install flow.
  --skip-docker     Skip Docker installation and group configuration.
  --skip-optional   Skip optional npm packages.
  -h, --help        Show this help message.
USAGE
}

installer_parse_args() {
	while (($#)); do
		case "$1" in
		--ci) CI_MODE=true ;;
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
  1. VALIDATE platform, version pins, CPU architecture, WSL status, and container context.
  2. DOWNLOAD package metadata and acquire a process lock, secure workspace, and backup directory.
  3. VERIFY package pins and existing runtime state where possible.
  4. INSTALL base packages, pinned Node.js, pinned Codex CLI, and optional Docker.
  5. CONFIGURE Codex config and shell integration.
  6. VERIFY_RUNTIME and write ${ZCODEX_MANIFEST_FILE}.
  7. COMPLETE with explicit state in ${ZCODEX_STATE_DIR}.
PLAN
	pins_summary
}

installer_cleanup() {
	local exit_code=$?
	if [[ "${DRY_RUN}" != "true" && "${INSTALLER_STATE_STARTED}" == "true" ]]; then
		if ((exit_code == 0)); then
			state_mark COMPLETE "installer completed" || true
			manifest_write complete || true
		else
			state_mark FAILED "exit_code=${exit_code}" || true
			manifest_write failed || true
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

installer_prepare_runtime() {
	state_mark DOWNLOAD "prepare runtime workspace"
	security_acquire_lock "${LOCK_FILE}"
	security_create_tmpdir >/dev/null
	backup_init >/dev/null
}

installer_verify_inputs() {
	if [[ -n "${INSTALLER_PREVIOUS_PHASE}" && "${INSTALLER_PREVIOUS_PHASE}" != "COMPLETE" ]]; then
		log_warn "Previous install state was incomplete at phase ${INSTALLER_PREVIOUS_PHASE}. Continuing deterministically."
	fi
	state_mark VERIFY "validate pins and interrupted state"
	pins_validate
}

installer_install_core() {
	state_mark INSTALL "install core runtime"
	packages_update
	packages_install_base
	nodejs_install_ubuntu
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

	docker_install_ubuntu
	docker_configure_user
}

installer_configure_codex() {
	state_mark CONFIGURE "configure codex runtime"
	codex_write_config
	shell_configure_codex
}

installer_verify_runtime() {
	state_mark VERIFY_RUNTIME "validate installed tools"
	codex_validate_cli || log_warn "Codex CLI validation did not pass in this environment."
	manifest_write running
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

	platform_validate
	pins_validate
	installer_planned_steps

	if [[ "${DRY_RUN}" == "true" ]]; then
		log_success "Dry run completed without making changes."
		return 0
	fi

	INSTALLER_PREVIOUS_PHASE="$(state_current_phase 2>/dev/null || true)"
	INSTALLER_STATE_STARTED=true
	state_mark VALIDATE "validate platform"
	installer_prepare_runtime
	installer_verify_inputs
	installer_install_core
	installer_install_optional_packages
	installer_install_docker
	installer_configure_codex
	installer_verify_runtime
}
