#!/usr/bin/env bash
# Installer orchestration helpers for the zcodex Ubuntu bootstrapper.

: "${SCRIPT_NAME:=$(basename "$0")}"
: "${CI_MODE:=${CI:-false}}"
: "${SKIP_DOCKER:=false}"
: "${SKIP_OPTIONAL:=false}"
: "${DRY_RUN:=false}"
: "${LOCK_FILE:=/tmp/zcodex-install.lock}"
: "${LOG_FILE:=/tmp/zcodex-install.log}"

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
  1. Validate Ubuntu release, CPU architecture, WSL status, and container runtime context.
  2. Acquire a process lock, secure temporary workspace, and backup directory.
  3. Update APT metadata and install base packages.
  4. Install Node.js/npm and the Codex CLI.
  5. Optionally install Docker.
  6. Write a minimal Codex config and shell integration.
PLAN
}

installer_cleanup() {
	local exit_code=$?
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
	security_acquire_lock "${LOCK_FILE}"
	security_create_tmpdir >/dev/null
	backup_init >/dev/null
}

installer_install_core() {
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
	codex_write_config
	shell_configure_codex
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

	platform_validate
	installer_planned_steps

	if [[ "${DRY_RUN}" == "true" ]]; then
		log_success "Dry run completed without making changes."
		return 0
	fi

	installer_prepare_runtime
	installer_install_core
	installer_install_optional_packages
	installer_install_docker
	installer_configure_codex
}
