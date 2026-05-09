#!/usr/bin/env bash
# Validate that the local zcodex runtime is ready.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
SCRIPT_NAME="$(basename "$0")"
LOG_FILE="${LOG_FILE:-/tmp/zcodex-doctor.log}"
CI_MODE="${CI_MODE:-${CI:-false}}"
ZCODEX_DOCTOR_TRUSTED_PATH="${ZCODEX_DOCTOR_TRUSTED_PATH:-${ZCODEX_CI_TRUSTED_PATH:-/usr/sbin:/usr/bin}}"
STRICT_MODE="${STRICT:-0}"
DOCTOR_OUTPUT_MODE="${DOCTOR_OUTPUT_MODE:-}"
OFFLINE_MODE=false
REPAIR_MODE=false
NETWORK_URL="${ZCODEX_DOCTOR_NETWORK_URL:-https://registry.npmjs.org/@openai%2fcodex}"
INFO_COUNT=0
WARN_COUNT=0
ERROR_COUNT=0
FATAL_COUNT=0
DIAGNOSTIC_COUNT=0

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
  --strict        Treat LOW/MEDIUM findings as failures. Also configurable with STRICT=1.
  --mode MODE     Output mode: human, ci, or debug. CI mode emits JSON only.
  -h, --help      Show this help message.
USAGE
}

parse_args() {
	while (($#)); do
		case "$1" in
		--offline) OFFLINE_MODE=true ;;
		--repair) REPAIR_MODE=true ;;
		--strict) STRICT_MODE=1 ;;
		--mode)
			shift
			if [[ $# -eq 0 ]]; then
				doctor_error "doctor.cli.invalid-mode" 75 "Missing value for --mode." "argument parsing" "Use --mode human, --mode ci, or --mode debug." false
				return 2
			fi
			DOCTOR_OUTPUT_MODE="$1"
			;;
		--mode=*) DOCTOR_OUTPUT_MODE="${1#--mode=}" ;;
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

doctor_normalize_mode() {
	if [[ -z "${DOCTOR_OUTPUT_MODE}" ]]; then
		if [[ "${CI_MODE}" == "true" ]]; then
			DOCTOR_OUTPUT_MODE=ci
		else
			DOCTOR_OUTPUT_MODE=human
		fi
	fi
	case "${DOCTOR_OUTPUT_MODE}" in
	human | ci | debug) ;;
	*)
		local invalid_mode="${DOCTOR_OUTPUT_MODE}"
		DOCTOR_OUTPUT_MODE=human
		doctor_error "doctor.cli.invalid-mode" 75 "Invalid doctor output mode requested." "mode=${invalid_mode}" "Use --mode human, --mode ci, or --mode debug." false
		return 2
		;;
	esac
}
doctor_is_json_only() { [[ "${DOCTOR_OUTPUT_MODE}" == "ci" ]]; }
doctor_is_debug() { [[ "${DOCTOR_OUTPUT_MODE}" == "debug" ]]; }

doctor_severity_for_score() {
	local score="$1"
	if ((score <= 20)); then
		printf 'INFO\n'
	elif ((score <= 40)); then
		printf 'LOW\n'
	elif ((score <= 60)); then
		printf 'MEDIUM\n'
	elif ((score <= 80)); then
		printf 'HIGH\n'
	else
		printf 'CRITICAL\n'
	fi
}

doctor_count_severity() {
	case "$1" in
	INFO) INFO_COUNT=$((INFO_COUNT + 1)) ;;
	LOW | MEDIUM) WARN_COUNT=$((WARN_COUNT + 1)) ;;
	HIGH) ERROR_COUNT=$((ERROR_COUNT + 1)) ;;
	CRITICAL) FATAL_COUNT=$((FATAL_COUNT + 1)) ;;
	esac
	DIAGNOSTIC_COUNT=$((DIAGNOSTIC_COUNT + 1))
}

doctor_json_bool() {
	case "$1" in
	true | TRUE | 1 | yes | YES) printf 'true' ;;
	*) printf 'false' ;;
	esac
}

doctor_diagnostic_json() {
	local check_id="$1" severity="$2" risk_score="$3" message="$4" context="$5" recommendation="$6" auto_fixable="$7"
	printf '{"check_id":"%s","severity":"%s","risk_score":%s,"message":"%s","context":"%s","recommendation":"%s","auto_fixable":%s}\n' \
		"$(log_json_escape "${check_id}")" \
		"$(log_json_escape "${severity}")" \
		"${risk_score}" \
		"$(log_json_escape "${message}")" \
		"$(log_json_escape "${context}")" \
		"$(log_json_escape "${recommendation}")" \
		"$(doctor_json_bool "${auto_fixable}")"
}

doctor_emit() {
	local check_id="$1" risk_score="$2" message="$3" context="$4" recommendation="$5" auto_fixable="$6"
	local severity
	severity="$(doctor_severity_for_score "${risk_score}")"
	doctor_count_severity "${severity}"
	if doctor_is_json_only; then
		doctor_diagnostic_json "${check_id}" "${severity}" "${risk_score}" "${message}" "${context}" "${recommendation}" "${auto_fixable}"
		return 0
	fi
	case "${severity}" in
	INFO) log_info "${check_id}: ${message}" ;;
	LOW | MEDIUM) log_warn "${check_id}: ${message}" ;;
	HIGH | CRITICAL) log_error "${check_id}: ${message}" ;;
	esac
	if doctor_is_debug; then
		log_info "${check_id}: context=${context}"
		log_info "${check_id}: recommendation=${recommendation} auto_fixable=$(doctor_json_bool "${auto_fixable}") risk_score=${risk_score} severity=${severity}"
		doctor_diagnostic_json "${check_id}" "${severity}" "${risk_score}" "${message}" "${context}" "${recommendation}" "${auto_fixable}" >&2
	fi
}

doctor_legacy_emit() {
	local default_id="$1" default_risk="$2" default_recommendation="$3"
	shift 3
	if (($# >= 6)); then
		doctor_emit "$1" "$2" "$3" "$4" "$5" "$6"
	else
		doctor_emit "${default_id}" "${default_risk}" "${1:-}" "general" "${default_recommendation}" false
	fi
}

doctor_info() { doctor_legacy_emit doctor.info 10 'No action required.' "$@"; }
doctor_ok() { doctor_legacy_emit doctor.ok 0 'No action required.' "$@"; }
doctor_warn() { doctor_legacy_emit doctor.warning 45 'Review the warning and apply the recommended remediation.' "$@"; }
doctor_error() { doctor_legacy_emit doctor.error 75 'Resolve this finding before continuing.' "$@"; }
doctor_fatal() { doctor_legacy_emit doctor.fatal 90 'Resolve this critical finding before continuing.' "$@"; }

check_command() {
	local name="$1"
	local required="${2:-required}"
	local hint

	if runtime_command_exists "${name}"; then
		doctor_ok "doctor.command.${name}" 0 "${name} found: $(command -v "${name}")" "command=${name}" "No action required." false
		return 0
	fi

	hint="$(dependency_install_hint "${name}")"
	if [[ "${required}" == "optional" ]]; then
		doctor_warn "doctor.command.${name}.optional-missing" 35 "${name} is missing (optional). ${hint}" "command=${name} required=${required}" "${hint}" true
		return 0
	fi

	doctor_error "doctor.command.${name}.missing" 75 "${name} is missing. ${hint}" "command=${name} required=${required}" "${hint}" true
	return 1
}

doctor_user_writable_path_entries() {
	local path_value="${1:-${PATH:-}}"
	local entry canonical entries=()
	while IFS= read -r entry; do
		[[ -n "${entry}" ]] || continue
		case "${entry}" in
		/*) ;;
		*) continue ;;
		esac
		canonical="$(security_canonical_path_entry "${entry}" 2>/dev/null || true)"
		[[ -n "${canonical}" ]] || continue
		if security_path_entry_is_safe_prefix "${canonical}"; then
			continue
		fi
		if security_path_entry_is_writable_by_untrusted "${canonical}"; then
			entries+=("${canonical}")
		fi
	done < <(security_path_split "${path_value}")

	local IFS=', '
	printf '%s\n' "${entries[*]}"
}

check_path() {
	local canonical user_entries

	if security_validate_path "${PATH:-}" safe; then
		canonical="$(security_canonicalize_path "${PATH:-}")"
		doctor_ok "doctor.path.valid" 0 "PATH validation passed for non-privileged doctor context: ${canonical}" "PATH=${canonical}" "No action required." false
		user_entries="$(doctor_user_writable_path_entries "${PATH:-}")"
		if [[ -n "${user_entries}" ]]; then
			doctor_warn "doctor.path.user-writable" 40 "User-local PATH entries detected: ${user_entries}" "entries=${user_entries}" "Move writable user-local entries after trusted system paths before privileged operations." false
		fi
		doctor_info "doctor.path.privileged-validation" 10 "No privileged injection risk detected by doctor; installer performs strict PATH validation before privileged operations." "PATH=${PATH:-}" "No action required." false
		return 0
	fi

	doctor_error "doctor.path.invalid" 80 "PATH failed structural validation. Use absolute, existing directories and remove empty segments." "PATH=${PATH:-}" "Remove empty, relative, missing, group-writable, or world-writable PATH entries." true
	return 1
}

doctor_prepare_command_path() {
	if [[ "${CI_MODE}" == "true" && "${ZCODEX_ALLOW_INSECURE_PATH:-false}" != "true" ]]; then
		doctor_warn "doctor.path.ci-sanitized" 35 "CI mode detected; replacing PATH with trusted system directories before validation." "trusted_path=${ZCODEX_DOCTOR_TRUSTED_PATH}" "Set ZCODEX_ALLOW_INSECURE_PATH=true only for controlled debugging; otherwise keep the trusted CI PATH." false
		export PATH="${ZCODEX_DOCTOR_TRUSTED_PATH}"
	fi
}

check_shell() {
	local shell_path="${SHELL:-}"
	local shell_name

	if [[ -z "${shell_path}" ]]; then
		doctor_warn "doctor.shell.unset" 35 "SHELL is not set. Set SHELL to your interactive shell if shell integration behaves unexpectedly." "SHELL unset" "Export SHELL to the absolute path of bash or zsh." true
		return 0
	fi

	shell_name="$(basename "${shell_path}")"
	case "${shell_name}" in
	bash | zsh)
		doctor_ok "doctor.shell.supported" 0 "Interactive shell is supported: ${shell_path}" "SHELL=${shell_path}" "No action required." false
		;;
	*)
		doctor_warn "doctor.shell.unsupported" 35 "Interactive shell may need manual configuration: ${shell_path}. Bash and zsh are supported automatically." "SHELL=${shell_path}" "Use bash or zsh, or manually add the Codex shell integration to your shell profile." false
		;;
	esac
}

check_permissions() {
	if [[ "${EUID}" -eq 0 ]]; then
		doctor_ok "doctor.permissions.root" 0 "Running as root; package operations are available." "EUID=${EUID}" "No action required." false
		return 0
	fi

	if runtime_command_exists sudo && sudo -n true >/dev/null 2>&1; then
		doctor_ok "doctor.permissions.sudo" 0 "Passwordless sudo is available for package operations." "EUID=${EUID}" "No action required." false
		return 0
	fi

	doctor_warn "doctor.permissions.sudo-interactive" 45 "sudo is unavailable or requires interaction; installer package operations may pause for credentials." "EUID=${EUID}" "Configure passwordless sudo for unattended installs, or run interactively." false
}

check_release_tooling() {
	local command_name
	local missing=0

	doctor_info "doctor.tooling.start" 10 "Checking development/release tooling. Missing tools are WARN by default; run make validate-env for a hard gate." "tools=${ZCODEX_REQUIRED_TOOLING[*]}" "Run make validate-env for a hard dependency gate." false
	for command_name in "${ZCODEX_REQUIRED_TOOLING[@]}"; do
		if runtime_command_exists "${command_name}"; then
			doctor_ok "doctor.tooling.${command_name}" 0 "$(dependency_command_description "${command_name}") found: $(command -v "${command_name}")" "command=${command_name}" "No action required." false
			continue
		fi

		doctor_warn "doctor.tooling.${command_name}.missing" 45 "$(dependency_command_description "${command_name}") is missing. $(dependency_install_hint "${command_name}")" "command=${command_name}" "$(dependency_install_hint "${command_name}")" true
		missing=$((missing + 1))
	done

	if ((missing > 0)); then
		doctor_info "doctor.tooling.remediation" 10 "Ubuntu remediation for development and release tooling: make deps-dev" "missing=${missing}" "Run make deps-dev." true
	else
		doctor_ok "doctor.tooling.complete" 0 "Development and release tooling is available." "missing=0" "No action required." false
	fi
}

check_network() {
	if [[ "${OFFLINE_MODE}" == "true" ]]; then
		doctor_warn "doctor.network.offline" 35 "Skipping network check because --offline was provided." "offline=true" "Rerun without --offline when external registry validation is required." false
		return 0
	fi

	if ! runtime_command_exists curl; then
		doctor_error "doctor.network.curl-missing" 75 "curl is missing; cannot verify network access. Install curl: sudo apt install curl" "command=curl" "Install curl: sudo apt install curl" true
		return 1
	fi

	if curl --fail --silent --show-error --location --max-time 8 --head "${NETWORK_URL}" >/dev/null; then
		doctor_ok "doctor.network.available" 0 "Network access verified: ${NETWORK_URL}" "url=${NETWORK_URL}" "No action required." false
		return 0
	fi

	doctor_warn "doctor.network.unavailable" 50 "Network check failed: ${NETWORK_URL}. If this host is offline or proxied, rerun with --offline." "url=${NETWORK_URL}" "Verify proxy/firewall settings or rerun with --offline for airgapped hosts." false
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
	if ! doctor_is_json_only; then
		log_section 'zcodex repair'
	fi
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

	doctor_info "doctor.platform.context" 10 "Platform context: $(platform_context_summary)" "arch=$(platform_arch) os=$(platform_pretty_name)" "No action required." false

	if ! platform_is_supported_arch; then
		doctor_error "doctor.platform.arch.unsupported" 85 "Unsupported architecture: $(platform_arch). Supported architectures: x86_64/amd64 and aarch64/arm64." "arch=$(platform_arch)" "Use a supported amd64 or arm64 Ubuntu host." false
	fi
	if ! supports_apt; then
		doctor_error "doctor.platform.package-runtime.unsupported" 85 "Unsupported package runtime. zcodex currently requires APT capability (apt-get and dpkg-query)." "apt=$(command -v apt-get 2>/dev/null || true) dpkg=$(command -v dpkg-query 2>/dev/null || true)" "Run zcodex on an APT-based Ubuntu host." false
	fi

	if platform_is_supported_ubuntu; then
		doctor_ok "doctor.platform.ubuntu-supported" 0 "Ubuntu-first platform detected: $(platform_pretty_name)." "platform=$(platform_pretty_name)" "No action required." false
	else
		doctor_warn "doctor.platform.ubuntu-unsupported" 50 "$(platform_pretty_name) is not a primary zcodex target. Continuing because required capabilities are present; package behavior is best-effort and unsupported." "platform=$(platform_pretty_name)" "Use Ubuntu 22.04 or 24.04 for production installs." false
	fi

	if platform_is_wsl; then
		doctor_warn "doctor.platform.wsl" 45 "WSL environment detected; Docker and shell integration behavior may differ from native Linux." "wsl=true" "Validate Docker Desktop and shell profile behavior manually on WSL." false
	fi

	runtime="$(platform_container_runtime)"
	if [[ "${runtime}" != "none" ]]; then
		doctor_warn "doctor.platform.container" 45 "Container runtime detected (${runtime}); service management and Docker setup may be limited." "runtime=${runtime}" "Run on a host VM for full service-management validation." false
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
	if ! doctor_is_json_only; then
		log_section 'zcodex doctor summary'
	fi
	if strict_enabled; then
		doctor_info 'Strict mode: enabled (WARN findings fail the doctor run).'
	else
		doctor_info 'Strict mode: disabled (WARN findings are reported but do not fail the doctor run).'
	fi
	if ! doctor_is_json_only; then
		printf 'Summary: INFO=%s WARN=%s ERROR=%s FATAL=%s\n' "${INFO_COUNT}" "${WARN_COUNT}" "${ERROR_COUNT}" "${FATAL_COUNT}" >&2
	fi

	if ((FATAL_COUNT > 0 || ERROR_COUNT > 0)); then
		if doctor_is_json_only; then
			doctor_diagnostic_json doctor.summary HIGH 75 'Doctor failed: resolve ERROR/FATAL findings above.' "INFO=${INFO_COUNT} WARN=${WARN_COUNT} ERROR=${ERROR_COUNT} FATAL=${FATAL_COUNT}" 'Resolve every HIGH or CRITICAL diagnostic and rerun doctor.' false
		else
			log_error 'Doctor failed: resolve ERROR/FATAL findings above.'
		fi
		return 1
	fi
	if strict_enabled && ((WARN_COUNT > 0)); then
		if doctor_is_json_only; then
			doctor_diagnostic_json doctor.summary MEDIUM 55 'Doctor failed in strict mode: resolve LOW/MEDIUM findings above or rerun without --strict.' "INFO=${INFO_COUNT} WARN=${WARN_COUNT} ERROR=${ERROR_COUNT} FATAL=${FATAL_COUNT}" 'Resolve every LOW or MEDIUM diagnostic for strict mode, or disable strict mode for advisory-only findings.' false
		else
			log_error 'Doctor failed in strict mode: resolve WARN findings above or rerun without --strict.'
		fi
		return 1
	fi
	if ((WARN_COUNT > 0)); then
		if doctor_is_json_only; then
			doctor_diagnostic_json doctor.summary LOW 35 'Doctor passed with warnings.' "INFO=${INFO_COUNT} WARN=${WARN_COUNT} ERROR=${ERROR_COUNT} FATAL=${FATAL_COUNT}" 'Review LOW/MEDIUM diagnostics when practical.' false
		else
			log_warn 'Doctor passed with warnings. Review WARN findings when practical.'
		fi
	else
		if doctor_is_json_only; then
			doctor_diagnostic_json doctor.summary INFO 0 'Doctor passed without warnings.' "INFO=${INFO_COUNT} WARN=${WARN_COUNT} ERROR=${ERROR_COUNT} FATAL=${FATAL_COUNT}" 'No action required.' false
		else
			log_success 'Doctor passed without warnings.'
		fi
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
	doctor_normalize_mode || return $?
	if ! doctor_is_json_only; then
		log_section 'zcodex doctor'
	fi
	doctor_prepare_command_path
	if [[ "${REPAIR_MODE}" == "true" ]]; then
		run_repairs
	fi
	run_checks
	print_summary
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	main "$@"
fi
