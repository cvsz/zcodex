#!/usr/bin/env bash
# zcodex Ubuntu installer orchestration layer.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
SCRIPT_NAME="$(basename "$0")"
LOG_FILE="${LOG_FILE:-/tmp/zcodex-install.log}"
CI_MODE="${CI_MODE:-${CI:-false}}"
SKIP_DOCKER=false
SKIP_OPTIONAL=false
DRY_RUN=false
LOCK_FILE="${LOCK_FILE:-/tmp/zcodex-install.lock}"

# shellcheck source=scripts/lib/logging.sh
. "${LIB_DIR}/logging.sh"
# shellcheck source=scripts/lib/retry.sh
. "${LIB_DIR}/retry.sh"
# shellcheck source=scripts/lib/platform.sh
. "${LIB_DIR}/platform.sh"
# shellcheck source=scripts/lib/security.sh
. "${LIB_DIR}/security.sh"
# shellcheck source=scripts/lib/packages.sh
. "${LIB_DIR}/packages.sh"
# shellcheck source=scripts/lib/nodejs.sh
. "${LIB_DIR}/nodejs.sh"
# shellcheck source=scripts/lib/docker.sh
. "${LIB_DIR}/docker.sh"
# shellcheck source=scripts/lib/codex.sh
. "${LIB_DIR}/codex.sh"
# shellcheck source=scripts/lib/shell.sh
. "${LIB_DIR}/shell.sh"

usage() {
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

parse_args() {
	while (($#)); do
		case "$1" in
		--ci) CI_MODE=true ;;
		--dry-run) DRY_RUN=true ;;
		--skip-docker) SKIP_DOCKER=true ;;
		--skip-optional) SKIP_OPTIONAL=true ;;
		-h | --help)
			usage
			exit 0
			;;
		*)
			log_error "Unknown option: $1"
			usage
			return 2
			;;
		esac
		shift
	done
}

planned_steps() {
	cat <<PLAN
Install flow:
  1. Validate Ubuntu release, CPU architecture, WSL status, and container runtime context.
  2. Acquire a process lock and secure temporary workspace.
  3. Update APT metadata and install base packages.
  4. Install Node.js/npm and the Codex CLI.
  5. Optionally install Docker.
  6. Write a minimal Codex config and shell integration.
PLAN
}

cleanup() {
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

main() {
	logging_init
	parse_args "$@"
	log_section "zcodex installer"

	platform_validate
	planned_steps

	if [[ "${DRY_RUN}" == "true" ]]; then
		log_success "Dry run completed without making changes."
		return 0
	fi

	security_acquire_lock "${LOCK_FILE}"
	security_create_tmpdir >/dev/null

	packages_update
	packages_install_base
	nodejs_install_ubuntu
	codex_install_cli

	if [[ "${SKIP_OPTIONAL}" != "true" ]]; then
		nodejs_install_global_packages npm-check-updates
	fi

	if [[ "${SKIP_DOCKER}" != "true" ]]; then
		docker_install_ubuntu
		docker_configure_user
	else
		log_info "Skipping Docker installation."
	fi

	codex_write_config
	shell_configure_codex
	codex_validate_cli || log_warn "Codex CLI validation did not pass in this environment."
}

trap cleanup EXIT
main "$@"
