#!/usr/bin/env bash
# Validate that the local zcodex runtime is ready.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
SCRIPT_NAME="$(basename "$0")"
LOG_FILE="${LOG_FILE:-/tmp/zcodex-doctor.log}"
CI_MODE="${CI_MODE:-${CI:-false}}"
FAILED=0
OFFLINE_MODE=false
NETWORK_URL="${ZCODEX_DOCTOR_NETWORK_URL:-https://registry.npmjs.org/@openai%2fcodex}"

# shellcheck source=scripts/lib/logging.sh
. "${LIB_DIR}/logging.sh"
# shellcheck source=scripts/lib/platform.sh
. "${LIB_DIR}/platform.sh"

usage() {
	cat <<USAGE
Usage: ${SCRIPT_NAME} [OPTIONS]

Options:
  --offline       Skip outbound network checks for airgapped/proxied systems.
  -h, --help      Show this help message.
USAGE
}

parse_args() {
	while (($#)); do
		case "$1" in
		--offline) OFFLINE_MODE=true ;;
		-h | --help)
			usage
			return 64
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

record_failure() {
	FAILED=1
}

check_command() {
	local name="$1"
	local required="${2:-required}"

	if command_exists "${name}"; then
		log_success "${name} found: $(command -v "${name}")"
		return 0
	fi

	if [[ "${required}" == "optional" ]]; then
		log_warn "${name} is missing (optional)."
		return 0
	fi

	log_warn "${name} is missing."
	record_failure
	return 1
}

path_entry_is_insecure() {
	local entry="$1"
	local mode

	[[ -d "${entry}" ]] || return 1
	mode="$(stat -c '%a' "${entry}" 2>/dev/null || printf '0')"
	# The final two permission digits are group and other. Values 2, 3, 6,
	# and 7 include write permissions and are unsafe for executable lookup paths.
	case "${mode: -2:1}${mode: -1}" in
	*[2367]*) return 0 ;;
	*) return 1 ;;
	esac
}

check_path() {
	local path_value="${PATH:-}"
	local entry
	local missing=0
	local insecure=0
	local invalid=0

	if [[ -z "${path_value}" ]]; then
		log_warn "PATH is empty."
		record_failure
		return 1
	fi

	if [[ "${path_value}" == *::* || "${path_value}" == :* || "${path_value}" == *: ]]; then
		log_warn "PATH contains an empty entry, which resolves to the current directory."
		invalid=1
	fi

	while IFS= read -r -d '' entry; do
		[[ -n "${entry}" ]] || continue
		if [[ ! -d "${entry}" ]]; then
			log_warn "PATH entry does not exist: ${entry}"
			missing=1
			continue
		fi
		if path_entry_is_insecure "${entry}"; then
			log_warn "PATH entry is group/other writable: ${entry}"
			insecure=1
		fi
	done < <(printf '%s' "${path_value}" | tr ':' '\0')

	if ((missing == 0 && insecure == 0 && invalid == 0)); then
		log_success "PATH entries are present and not group/other writable."
		return 0
	fi

	record_failure
	return 1
}

check_shell() {
	local shell_path="${SHELL:-}"
	local shell_name

	if [[ -z "${shell_path}" ]]; then
		log_warn "SHELL is not set."
		record_failure
		return 1
	fi

	shell_name="$(basename "${shell_path}")"
	case "${shell_name}" in
	bash | zsh)
		log_success "Interactive shell is supported: ${shell_path}"
		;;
	*)
		log_warn "Interactive shell may need manual configuration: ${shell_path}"
		;;
	esac
}

check_permissions() {
	if [[ "${EUID}" -eq 0 ]]; then
		log_success "Running as root; package operations are available."
		return 0
	fi

	if command_exists sudo && sudo -n true >/dev/null 2>&1; then
		log_success "Passwordless sudo is available for package operations."
		return 0
	fi

	log_warn "sudo is unavailable or requires interaction; installer package operations may pause for credentials."
}

check_network() {
	if [[ "${OFFLINE_MODE}" == "true" ]]; then
		log_warn "Skipping network check because --offline was provided."
		return 0
	fi

	if ! command_exists curl; then
		log_warn "curl is missing; cannot verify network access."
		record_failure
		return 1
	fi

	if curl --fail --silent --show-error --location --max-time 8 --head "${NETWORK_URL}" >/dev/null; then
		log_success "Network access verified: ${NETWORK_URL}"
		return 0
	fi

	log_warn "Network check failed: ${NETWORK_URL}"
	record_failure
	return 1
}

check_versions() {
	if command_exists node; then
		log_info "node version: $(node --version 2>/dev/null || true)"
	fi
	if command_exists npm; then
		log_info "npm version: $(npm --version 2>/dev/null || true)"
	fi
	if command_exists codex; then
		log_info "codex version: $(codex --version 2>/dev/null || true)"
	fi
	if command_exists docker; then
		log_info "docker version: $(docker --version 2>/dev/null || true)"
	fi
}

run_checks() {
	platform_validate || record_failure
	check_path || true
	check_shell || true
	check_permissions
	check_command bash || true
	check_command curl || true
	check_command git || true
	check_command node || true
	check_command npm || true
	check_command codex || true
	check_command docker optional
	check_network || true
	check_versions
	return "${FAILED}"
}

main() {
	local parse_status

	logging_init
	parse_args "$@" || {
		parse_status="$?"
		case "${parse_status}" in
		64) return 0 ;;
		*) return "${parse_status}" ;;
		esac
	}
	log_section "zcodex doctor"
	run_checks
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	main "$@"
fi
