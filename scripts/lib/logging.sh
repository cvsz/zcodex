#!/usr/bin/env bash
# Shared structured logging helpers.

: "${CI_MODE:=${CI:-false}}"
: "${LOG_FILE:=/tmp/zcodex-install.log}"
readonly ZCODEX_LOG_ERR_INVALID_DEST=70

LOG_COLOR_RED=''
LOG_COLOR_GREEN=''
LOG_COLOR_YELLOW=''
LOG_COLOR_BLUE=''
LOG_COLOR_CYAN=''
LOG_COLOR_BOLD=''
LOG_COLOR_RESET=''

log_timestamp() {
	if [[ -n "${ZCODEX_FIXED_TIMESTAMP:-}" ]]; then
		printf '%s\n' "${ZCODEX_FIXED_TIMESTAMP}"
	else
		date -u '+%Y-%m-%dT%H:%M:%SZ'
	fi
}

logging_init() {
	local logfile="${1:-${LOG_FILE}}"
	local logdir

	if [[ -z "${logfile}" ]]; then
		printf 'logging_init: log file path must not be empty\n' >&2
		return "${ZCODEX_LOG_ERR_INVALID_DEST}"
	fi

	logdir="$(dirname -- "${logfile}")"
	if [[ ! -d "${logdir}" ]]; then
		mkdir -p -- "${logdir}" 2>/dev/null || {
			printf 'logging_init: log directory does not exist: %s\n' "${logdir}" >&2
			return "${ZCODEX_LOG_ERR_INVALID_DEST}"
		}
	fi

	: >>"${logfile}" 2>/dev/null || {
		printf 'logging_init: log file is not writable: %s\n' "${logfile}" >&2
		return "${ZCODEX_LOG_ERR_INVALID_DEST}"
	}

	ZCODEX_LOG_FILE="${logfile}"

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
	local destination="${ZCODEX_LOG_FILE:-${LOG_FILE}}"
	timestamp="$(log_timestamp)"
	printf '[%s] [%s] %s\n' "${timestamp}" "${level}" "${message}" >>"${destination}"
	printf '%s\n' "${message}" >&2
}

log_info() { log_write INFO "${LOG_COLOR_BLUE}[INFO]${LOG_COLOR_RESET} $*"; }
log_success() { log_write OK "${LOG_COLOR_GREEN}[OK]${LOG_COLOR_RESET} $*"; }
log_warn() { log_write WARN "${LOG_COLOR_YELLOW}[WARN]${LOG_COLOR_RESET} $*"; }
log_error() { log_write ERROR "${LOG_COLOR_RED}[ERROR]${LOG_COLOR_RESET} $*"; }
log_section() { log_write SECTION "${LOG_COLOR_BOLD}${LOG_COLOR_CYAN}== $* ==${LOG_COLOR_RESET}"; }

log_json_escape() {
	local value="$1"
	value="${value//\\/\\\\}"
	value="${value//\"/\\\"}"
	value="${value//$'\n'/\\n}"
	value="${value//$'\r'/\\r}"
	value="${value//$'\t'/\\t}"
	printf '%s' "${value}"
}

log_json() {
	local level="$1"
	shift
	local message="$*"
	local timestamp
	timestamp="$(log_timestamp)"
	printf '{"timestamp":"%s","level":"%s","message":"%s"}\n' \
		"${timestamp}" \
		"$(log_json_escape "${level}")" \
		"$(log_json_escape "${message}")"
}
