#!/usr/bin/env bash
# Remove Codex CLI artifacts installed by zcodex.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
LOG_FILE="${LOG_FILE:-/tmp/zcodex-uninstall.log}"
CI_MODE="${CI_MODE:-${CI:-false}}"
REMOVE_CONFIG=false

# shellcheck source=scripts/lib/logging.sh
. "${LIB_DIR}/logging.sh"
# shellcheck source=scripts/lib/retry.sh
. "${LIB_DIR}/retry.sh"
# shellcheck source=scripts/lib/platform.sh
. "${LIB_DIR}/platform.sh"

usage() {
	cat <<USAGE
Usage: uninstall-codex.sh [--remove-config]

Options:
  --remove-config   Remove ~/.codex after uninstalling the npm package.
USAGE
}

parse_args() {
	while (($#)); do
		case "$1" in
		--remove-config) REMOVE_CONFIG=true ;;
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

main() {
	logging_init
	parse_args "$@"
	if command_exists npm; then
		retry 3 2 sudo npm uninstall --global @openai/codex || log_warn "Codex npm package was not installed globally."
	fi
	if [[ "${REMOVE_CONFIG}" == "true" ]]; then
		rm -rf "${CODEX_HOME:-${HOME}/.codex}"
		log_success "Removed Codex configuration directory."
	fi
}

main "$@"
