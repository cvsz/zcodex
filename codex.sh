#!/usr/bin/env bash
# Unified zcodex release orchestrator for operational install modes.

set -Eeuo pipefail

ZCODEX_RELEASE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ZCODEX_RELEASE_SCRIPT_DIR
readonly ZCODEX_RELEASE_LIB_DIR="${ZCODEX_RELEASE_SCRIPT_DIR}/scripts/lib"
ZCODEX_RELEASE_SCRIPT_NAME="$(basename "$0")"
readonly ZCODEX_RELEASE_SCRIPT_NAME
ZCODEX_RELEASE_LOG_FILE="${ZCODEX_RELEASE_LOG:-${LOG_FILE:-${ZCODEX_RELEASE_SCRIPT_DIR}/codex_release.log}}"

# shellcheck source=scripts/lib/exec.sh
. "${ZCODEX_RELEASE_LIB_DIR}/exec.sh"

usage() {
	cat <<USAGE
Usage: ${ZCODEX_RELEASE_SCRIPT_NAME} {basic|full|ultimate|orchestrator|release} [ARGS...]

Modes:
  basic         Run the Ubuntu Codex installer with any extra installer args.
  full          Run the installer, then an offline doctor check.
  ultimate      Validate the environment, run the installer, then doctor online.
  orchestrator  Run doctor with any extra doctor args.
  release       Run the installer, then doctor online for release validation.

Examples:
  ${ZCODEX_RELEASE_SCRIPT_NAME} basic --dry-run --skip-docker
  ${ZCODEX_RELEASE_SCRIPT_NAME} orchestrator --offline --repair
  ${ZCODEX_RELEASE_SCRIPT_NAME} release --skip-optional
USAGE
}

release_log_prepare() {
	local log_dir
	log_dir="$(dirname "${ZCODEX_RELEASE_LOG_FILE}")"
	mkdir -p "${log_dir}"
}

log() {
	local message="$1"
	release_log_prepare
	printf '[Codex] %s\n' "${message}" | tee -a "${ZCODEX_RELEASE_LOG_FILE}"
}

run_step() {
	local description="$1"
	shift

	release_log_prepare
	LOG_FILE="${ZCODEX_RELEASE_LOG_FILE}" runtime_exec_logged "${ZCODEX_RELEASE_LOG_FILE}" "${description}" env LOG_FILE="${ZCODEX_RELEASE_LOG_FILE}" "$@"
}

require_local_script() {
	local script_path="$1"
	if [[ ! -x "${script_path}" && ! -f "${script_path}" ]]; then
		printf 'Required script is missing: %s\n' "${script_path}" >&2
		return 1
	fi
}

validate_orchestrator_environment() {
	log "Validating orchestrator environment..."
	runtime_command_exists bash || {
		printf 'bash is required. Aborting.\n' >&2
		return 1
	}
	runtime_command_exists kubectl || log "Warning: Kubernetes not found, skipping cluster orchestration."
	if ! runtime_command_exists docker; then
		log "Warning: Docker not found; installer/doctor will handle Docker according to selected flags."
	fi
	if ! runtime_command_exists node; then
		log "Warning: Node.js not found; installer can install it on supported Ubuntu hosts."
	fi
}

main() {
	local mode="${1:-}"
	local installer="${ZCODEX_RELEASE_SCRIPT_DIR}/scripts/install-codex-ubuntu.sh"
	local doctor="${ZCODEX_RELEASE_SCRIPT_DIR}/scripts/doctor.sh"
	local validator="${ZCODEX_RELEASE_SCRIPT_DIR}/scripts/validate-environment.sh"

	if [[ -z "${mode}" || "${mode}" == "-h" || "${mode}" == "--help" ]]; then
		usage
		return 0
	fi
	shift

	require_local_script "${installer}"
	require_local_script "${doctor}"
	require_local_script "${validator}"
	validate_orchestrator_environment

	case "${mode}" in
	basic)
		run_step "Running Basic Installation..." bash "${installer}" "$@"
		;;
	full)
		run_step "Running Full Installation..." bash "${installer}" "$@"
		run_step "Running Offline Doctor Validation..." bash "${doctor}" --offline
		;;
	ultimate)
		run_step "Running Environment Validation..." bash "${validator}"
		run_step "Running Ultimate Installation..." bash "${installer}" "$@"
		run_step "Running Doctor Validation..." bash "${doctor}"
		;;
	orchestrator)
		run_step "Running Master Orchestrator..." bash "${doctor}" "$@"
		;;
	release)
		run_step "Executing Final Release Installation..." bash "${installer}" "$@"
		run_step "Executing Final Release Validation..." bash "${doctor}"
		log "Release build complete. Artifacts logged in ${ZCODEX_RELEASE_LOG_FILE}"
		;;
	*)
		usage >&2
		return 2
		;;
	esac

	log "Process finished successfully."
}

main "$@"
