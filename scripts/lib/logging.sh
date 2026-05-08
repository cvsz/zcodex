#!/usr/bin/env bash
# Shared structured logging helpers.

: "${CI_MODE:=${CI:-false}}"
: "${LOG_FILE:=/tmp/zcodex-install.log}"

LOG_COLOR_RED=''
LOG_COLOR_GREEN=''
LOG_COLOR_YELLOW=''
LOG_COLOR_BLUE=''
LOG_COLOR_CYAN=''
LOG_COLOR_BOLD=''
LOG_COLOR_RESET=''

logging_init() {
	if [[ -t 2 && "${CI_MODE}" != "true" ]]; then
		LOG_COLOR_RED=$'\033[0;31m'
		LOG_COLOR_GREEN=$'\033[0;32m'
		LOG_COLOR_YELLOW=$'\033[1;33m'
		LOG_COLOR_BLUE=$'\033[0;34m'
		LOG_COLOR_CYAN=$'\033[0;36m'
		LOG_COLOR_BOLD=$'\033[1m'
		LOG_COLOR_RESET=$'\033[0m'
	fi
}

log_write() {
	local level="$1"
	shift
	local message="$*"
	local timestamp
	timestamp="$(date '+%Y-%m-%dT%H:%M:%S%z')"
	printf '[%s] [%s] %s\n' "${timestamp}" "${level}" "${message}" >>"${LOG_FILE}"
	printf '%s\n' "${message}" >&2
}

log_info() { log_write INFO "${LOG_COLOR_BLUE}[INFO]${LOG_COLOR_RESET} $*"; }
log_success() { log_write OK "${LOG_COLOR_GREEN}[OK]${LOG_COLOR_RESET} $*"; }
log_warn() { log_write WARN "${LOG_COLOR_YELLOW}[WARN]${LOG_COLOR_RESET} $*"; }
log_error() { log_write ERROR "${LOG_COLOR_RED}[ERROR]${LOG_COLOR_RESET} $*"; }
log_section() { log_write SECTION "${LOG_COLOR_BOLD}${LOG_COLOR_CYAN}== $* ==${LOG_COLOR_RESET}"; }
