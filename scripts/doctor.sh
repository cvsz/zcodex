#!/usr/bin/env bash
# Validate that the local zcodex runtime is ready.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
SCRIPT_NAME="$(basename "$0")"
LOG_FILE="${LOG_FILE:-/tmp/zcodex-doctor.log}"
CI_MODE="${CI_MODE:-${CI:-false}}"
STRICT_MODE="${STRICT:-0}"
OFFLINE_MODE=false
REPAIR_MODE=false
NETWORK_URL="${ZCODEX_DOCTOR_NETWORK_URL:-https://registry.npmjs.org/@openai%2fcodex}"
INFO_COUNT=0
WARN_COUNT=0
ERROR_COUNT=0
FATAL_COUNT=0

# shellcheck source=scripts/lib/runtime.sh
. "${LIB_DIR}/runtime.sh"
# shellcheck source=scripts/lib/dependencies.sh
. "${LIB_DIR}/dependencies.sh"

usage() {
	cat <<USAGE
Usage: ${SCRIPT_NAME} [OPTIONS]

Options:
  --offline       Skip outbound network checks for airgapped/proxied systems.
  --repair        Apply safe local repairs for Codex config and shell setup.
  --strict        Treat WARN findings as failures. Also configurable with STRICT=1.
  -h, --help      Show this help message.
USAGE
}

parse_args() {
	while (($#)); do
		case "$1" in
		--offline) OFFLINE_MODE=true ;;
		--repair) REPAIR_MODE=true ;;
		--strict) STRICT_MODE=1 ;;
		-h | --help)
			usage
			return 64
			;;
		*)
			doctor_error "Unknown option: $1"
			usage
			return 2
			;;
		esac
		shift
	done
}

strict_enabled() {
	case "${STRICT_MODE}" in
	1 | true | TRUE | yes | YES | on | ON) return 0 ;;
	*) return 1 ;;
	esac
}

doctor_info() {
	INFO_COUNT=$((INFO_COUNT + 1))
	log_info "$*"
}

doctor_ok() {
	log_success "$*"
}

doctor_warn() {
	WARN_COUNT=$((WARN_COUNT + 1))
	log_warn "$*"
}

doctor_error() {
	ERROR_COUNT=$((ERROR_COUNT + 1))
	log_error "$*"
}

doctor_fatal() {
	FATAL_COUNT=$((FATAL_COUNT + 1))
	log_error "FATAL: $*"
}

check_command() {
	local name="$1"
	local required="${2:-required}"
	local hint

	if runtime_command_exists "${name}"; then
		doctor_ok "${name} found: $(command -v "${name}")"
		return 0
	fi

	hint="$(dependency_install_hint "${name}")"
	if [[ "${required}" == "optional" ]]; then
		doctor_warn "${name} is missing (optional). ${hint}"
		return 0
	fi

	doctor_error "${name} is missing. ${hint}"
	return 1
}

check_path() {
	local canonical

	if security_validate_path "${PATH:-}"; then
		canonical="$(security_canonicalize_path "${PATH:-}")"
		doctor_ok "PATH is strict and canonicalizable: ${canonical}"
		return 0
	fi

	doctor_error 'PATH failed strict validation. Use absolute, existing, non-user-writable directories and remove empty segments.'
	return 1
}

check_shell() {
	local shell_path="${SHELL:-}"
	local shell_name

	if [[ -z "${shell_path}" ]]; then
		doctor_warn 'SHELL is not set. Set SHELL to your interactive shell if shell integration behaves unexpectedly.'
		return 0
	fi

	shell_name="$(basename "${shell_path}")"
	case "${shell_name}" in
	bash | zsh)
		doctor_ok "Interactive shell is supported: ${shell_path}"
		;;
	*)
		doctor_warn "Interactive shell may need manual configuration: ${shell_path}. Bash and zsh are supported automatically."
		;;
	esac
}

check_permissions() {
	if [[ "${EUID}" -eq 0 ]]; then
		doctor_ok 'Running as root; package operations are available.'
		return 0
	fi

	if runtime_command_exists sudo && sudo -n true >/dev/null 2>&1; then
		doctor_ok 'Passwordless sudo is available for package operations.'
		return 0
	fi

	doctor_warn 'sudo is unavailable or requires interaction; installer package operations may pause for credentials.'
}

check_release_tooling() {
	local command_name
	local missing=0

	doctor_info 'Checking development/release tooling. Missing tools are WARN by default; run make validate-env for a hard gate.'
	for command_name in "${ZCODEX_REQUIRED_TOOLING[@]}"; do
		if runtime_command_exists "${command_name}"; then
			doctor_ok "$(dependency_command_description "${command_name}") found: $(command -v "${command_name}")"
			continue
		fi

		doctor_warn "$(dependency_command_description "${command_name}") is missing. $(dependency_install_hint "${command_name}")"
		missing=$((missing + 1))
	done

	if ((missing > 0)); then
		doctor_info 'Ubuntu remediation for development and release tooling: make deps-dev'
	else
		doctor_ok 'Development and release tooling is available.'
	fi
}

check_network() {
	if [[ "${OFFLINE_MODE}" == "true" ]]; then
		doctor_warn 'Skipping network check because --offline was provided.'
		return 0
	fi

	if ! runtime_command_exists curl; then
		doctor_error 'curl is missing; cannot verify network access. Install curl: sudo apt install curl'
		return 1
	fi

	if curl --fail --silent --show-error --location --max-time 8 --head "${NETWORK_URL}" >/dev/null; then
		doctor_ok "Network access verified: ${NETWORK_URL}"
		return 0
	fi

	doctor_warn "Network check failed: ${NETWORK_URL}. If this host is offline or proxied, rerun with --offline."
	return 0
}

repair_codex_config() {
	local codex_home="${CODEX_HOME:-${HOME}/.codex}"
	local config_file="${codex_home}/config.toml"

	if [[ -f "${config_file}" ]]; then
		chmod 600 "${config_file}" || {
			doctor_error "Could not restrict ${config_file} permissions."
			return 1
		}
		doctor_ok "Repaired Codex config permissions: ${config_file}"
		return 0
	fi

	codex_write_config
}

repair_shell_profile() {
	if [[ "${CI_MODE}" == "true" ]]; then
		doctor_info 'Skipping shell profile repair in CI mode.'
		return 0
	fi
	shell_configure_codex
}

repair_manifest_state() {
	local phase
	local status

	phase="$(state_current_phase 2>/dev/null || true)"
	status="$(state_status 2>/dev/null || true)"
	if [[ -z "${phase}" ]]; then
		doctor_info 'No zcodex install state found; writing an audit manifest for current runtime.'
		repair_codex_config || true
		repair_shell_profile || true
		state_mark VERIFY_RUNTIME 'doctor repair initialized state' repair
		manifest_write repair
		return 0
	fi

	doctor_info "Repair context from install state: phase=${phase} status=${status:-unknown}."
	case "${phase}" in
	COMPLETE)
		manifest_write repair
		;;
	CONFIGURE | VERIFY_RUNTIME | FAILED)
		repair_codex_config || true
		repair_shell_profile || true
		manifest_write repair
		;;
	VALIDATE | DOWNLOAD | VERIFY | INSTALL)
		doctor_warn "Install stopped during ${phase}; safe repair will refresh the manifest, but rerun scripts/install-codex-ubuntu.sh to finish package work."
		manifest_write repair
		;;
	*)
		doctor_warn "Unknown install phase ${phase}; refreshing manifest only."
		manifest_write repair
		;;
	esac
}

run_repairs() {
	log_section 'zcodex repair'
	repair_manifest_state || true
}

check_versions() {
	if runtime_command_exists node; then
		doctor_info "node version: $(node --version 2>/dev/null || true)"
	fi
	if runtime_command_exists npm; then
		doctor_info "npm version: $(npm --version 2>/dev/null || true)"
	fi
	if runtime_command_exists codex; then
		doctor_info "codex version: $(codex --version 2>/dev/null || true)"
	fi
	if runtime_command_exists docker; then
		doctor_info "docker version: $(docker --version 2>/dev/null || true)"
	fi
}

check_platform() {
	local runtime

	doctor_info "Platform context: $(platform_context_summary)"

	if ! platform_is_supported_arch; then
		doctor_error "Unsupported architecture: $(platform_arch). Supported architectures: x86_64/amd64 and aarch64/arm64."
	fi
	if ! supports_apt; then
		doctor_error 'Unsupported package runtime. zcodex currently requires APT capability (apt-get and dpkg-query).'
	fi

	if platform_is_supported_ubuntu; then
		doctor_ok "Ubuntu-first platform detected: $(platform_pretty_name)."
	else
		doctor_warn "$(platform_pretty_name) is not a primary zcodex target. Continuing because required capabilities are present; package behavior is best-effort and unsupported."
	fi

	if platform_is_wsl; then
		doctor_warn 'WSL environment detected; Docker and shell integration behavior may differ from native Linux.'
	fi

	runtime="$(platform_container_runtime)"
	if [[ "${runtime}" != "none" ]]; then
		doctor_warn "Container runtime detected (${runtime}); service management and Docker setup may be limited."
	fi
}

run_checks() {
	check_platform || true
	check_path || true
	check_shell || true
	check_permissions || true
	check_command bash || true
	check_command curl || true
	check_command git || true
	check_release_tooling || true
	check_command node optional || true
	check_command npm optional || true
	check_command codex optional || true
	check_command docker optional || true
	check_network || true
	check_versions
}

print_summary() {
	log_section 'zcodex doctor summary'
	if strict_enabled; then
		doctor_info 'Strict mode: enabled (WARN findings fail the doctor run).'
	else
		doctor_info 'Strict mode: disabled (WARN findings are reported but do not fail the doctor run).'
	fi
	printf 'Summary: INFO=%s WARN=%s ERROR=%s FATAL=%s\n' "${INFO_COUNT}" "${WARN_COUNT}" "${ERROR_COUNT}" "${FATAL_COUNT}" >&2

	if ((FATAL_COUNT > 0 || ERROR_COUNT > 0)); then
		log_error 'Doctor failed: resolve ERROR/FATAL findings above.'
		return 1
	fi
	if strict_enabled && ((WARN_COUNT > 0)); then
		log_error 'Doctor failed in strict mode: resolve WARN findings above or rerun without --strict.'
		return 1
	fi
	if ((WARN_COUNT > 0)); then
		log_warn 'Doctor passed with warnings. Review WARN findings when practical.'
	else
		log_success 'Doctor passed without warnings.'
	fi
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
	log_section 'zcodex doctor'
	if [[ "${REPAIR_MODE}" == "true" ]]; then
		run_repairs
	fi
	run_checks
	print_summary
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	main "$@"
fi
