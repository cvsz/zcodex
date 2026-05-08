#!/usr/bin/env bash
# Unified zcodex release orchestrator for operational install modes.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "$0")"
LOG_FILE="${LOG_FILE:-${ZCODEX_RELEASE_LOG:-${SCRIPT_DIR}/codex_release.log}}"

usage() {
	cat <<USAGE
Usage: ${SCRIPT_NAME} {basic|full|ultimate|orchestrator|release} [ARGS...]

Modes:
  basic         Run the Ubuntu Codex installer with any extra installer args.
  full          Run the installer, then an offline doctor check.
  ultimate      Validate the environment, run the installer, then doctor online.
  orchestrator  Run doctor with any extra doctor args.
  release       Run the installer, then doctor online for release validation.

Examples:
  ${SCRIPT_NAME} basic --dry-run --skip-docker
  ${SCRIPT_NAME} orchestrator --offline --repair
  ${SCRIPT_NAME} release --skip-optional
USAGE
}

log() {
	local message="$1"
	printf '[Codex] %s\n' "${message}" | tee -a "${LOG_FILE}"
}

run_step() {
	local description="$1"
	shift

	log "${description}"
	LOG_FILE="${LOG_FILE}" "$@" 2>&1 | tee -a "${LOG_FILE}"
	return "${PIPESTATUS[0]}"
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
	command -v bash >/dev/null 2>&1 || {
		printf 'bash is required. Aborting.\n' >&2
		return 1
	}
	command -v kubectl >/dev/null 2>&1 || log "Warning: Kubernetes not found, skipping cluster orchestration."
	if ! command -v docker >/dev/null 2>&1; then
		log "Warning: Docker not found; installer/doctor will handle Docker according to selected flags."
	fi
	if ! command -v node >/dev/null 2>&1; then
		log "Warning: Node.js not found; installer can install it on supported Ubuntu hosts."
	fi
}

main() {
	local mode="${1:-}"
	local installer="${SCRIPT_DIR}/scripts/install-codex-ubuntu.sh"
	local doctor="${SCRIPT_DIR}/scripts/doctor.sh"
	local validator="${SCRIPT_DIR}/scripts/validate-environment.sh"

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
		log "Release build complete. Artifacts logged in ${LOG_FILE}"
		;;
	*)
		usage >&2
		return 2
		;;
	esac

	log "Process finished successfully."
}

main "$@"
