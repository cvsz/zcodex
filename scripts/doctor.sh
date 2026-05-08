#!/usr/bin/env bash
# Validate that the local zcodex runtime is ready.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
LOG_FILE="${LOG_FILE:-/tmp/zcodex-doctor.log}"
CI_MODE="${CI_MODE:-${CI:-false}}"
FAILED=0

# shellcheck source=scripts/lib/logging.sh
. "${LIB_DIR}/logging.sh"
# shellcheck source=scripts/lib/platform.sh
. "${LIB_DIR}/platform.sh"

check_command() {
	local name="$1"
	if command_exists "${name}"; then
		log_success "${name} found: $(command -v "${name}")"
	else
		log_warn "${name} is missing."
		FAILED=1
	fi
}

main() {
	logging_init
	log_section "zcodex doctor"
	platform_validate || FAILED=1
	check_command bash
	check_command curl
	check_command git
	check_command node
	check_command npm
	check_command codex
	return "${FAILED}"
}

main "$@"
