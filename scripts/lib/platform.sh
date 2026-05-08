#!/usr/bin/env bash
# Platform detection, capability registry, and validation helpers.

command_exists() {
	command -v "$1" >/dev/null 2>&1
}

platform_os_release_file() {
	printf '%s\n' "${ZCODEX_OS_RELEASE_FILE:-/etc/os-release}"
}

platform_proc_version_file() {
	printf '%s\n' "${ZCODEX_PROC_VERSION_FILE:-/proc/version}"
}

platform_arch() {
	uname -m
}

platform_arch_normalized() {
	case "$(platform_arch)" in
	x86_64 | amd64) printf '%s\n' amd64 ;;
	aarch64 | arm64) printf '%s\n' arm64 ;;
	*) printf '%s\n' unknown ;;
	esac
}

platform_is_supported_arch() {
	case "$(platform_arch_normalized)" in
	amd64 | arm64) return 0 ;;
	*) return 1 ;;
	esac
}

platform_os_id() {
	local os_release_file
	os_release_file="$(platform_os_release_file)"
	[[ -r "${os_release_file}" ]] || return 1
	# shellcheck disable=SC1090
	. "${os_release_file}"
	printf '%s\n' "${ID:-unknown}"
}

platform_os_version_id() {
	local os_release_file
	os_release_file="$(platform_os_release_file)"
	[[ -r "${os_release_file}" ]] || return 1
	# shellcheck disable=SC1090
	. "${os_release_file}"
	printf '%s\n' "${VERSION_ID:-unknown}"
}

platform_pretty_name() {
	local os_release_file
	os_release_file="$(platform_os_release_file)"
	if [[ -r "${os_release_file}" ]]; then
		# shellcheck disable=SC1090
		. "${os_release_file}"
		printf '%s\n' "${PRETTY_NAME:-${ID:-unknown} ${VERSION_ID:-}}"
		return 0
	fi
	printf '%s\n' 'unknown Linux'
}

platform_is_supported_ubuntu() {
	[[ "$(platform_os_id 2>/dev/null || true)" == "ubuntu" ]] || return 1
	case "$(platform_os_version_id 2>/dev/null || true)" in
	22.04 | 24.04) return 0 ;;
	*) return 1 ;;
	esac
}

platform_is_wsl() {
	local proc_version_file
	local proc_version=''
	proc_version_file="$(platform_proc_version_file)"

	if [[ -n "${WSL_DISTRO_NAME:-}" || -n "${WSL_INTEROP:-}" ]]; then
		return 0
	fi

	if [[ -r "${proc_version_file}" ]]; then
		proc_version="$(tr '[:upper:]' '[:lower:]' <"${proc_version_file}")"
		[[ "${proc_version}" == *microsoft* || "${proc_version}" == *wsl* ]] && return 0
	fi

	return 1
}

platform_container_runtime() {
	local cgroup_file="${ZCODEX_CGROUP_FILE:-/proc/1/cgroup}"
	local cgroup=''

	if [[ -n "${ZCODEX_CONTAINER_RUNTIME:-}" ]]; then
		printf '%s\n' "${ZCODEX_CONTAINER_RUNTIME}"
		return 0
	fi

	if [[ -f /.dockerenv ]]; then
		printf '%s\n' docker
		return 0
	fi

	if [[ -f /run/.containerenv ]]; then
		printf '%s\n' podman
		return 0
	fi

	if [[ -r "${cgroup_file}" ]]; then
		cgroup="$(tr '[:upper:]' '[:lower:]' <"${cgroup_file}")"
		case "${cgroup}" in
		*docker*) printf '%s\n' docker ;;
		*containerd*) printf '%s\n' containerd ;;
		*kubepods*) printf '%s\n' kubernetes ;;
		*libpod*) printf '%s\n' podman ;;
		*) printf '%s\n' none ;;
		esac
		return 0
	fi

	printf '%s\n' none
}

runtime_capability_names() {
	printf '%s\n' supports_apt supports_systemd supports_docker supports_rootless
}

supports_apt() {
	command_exists apt-get || return 1
	command_exists dpkg-query || return 1
}

supports_systemd() {
	command_exists systemctl || return 1
	[[ -d /run/systemd/system || "${ZCODEX_ASSUME_SYSTEMD:-false}" == "true" ]] || return 1
}

supports_docker() {
	if command_exists docker; then
		return 0
	fi

	# zcodex can install Docker only through the APT package path today.
	supports_apt || return 1
}

supports_rootless() {
	[[ "${EUID}" -ne 0 ]] || return 1
	[[ -n "${HOME:-}" && -d "${HOME}" && -w "${HOME}" ]] || return 1
	command_exists sudo || return 1
}

runtime_capability_supported() {
	case "$1" in
	supports_apt) supports_apt ;;
	supports_systemd) supports_systemd ;;
	supports_docker) supports_docker ;;
	supports_rootless) supports_rootless ;;
	*) return 2 ;;
	esac
}

runtime_capability_status() {
	if runtime_capability_supported "$1"; then
		printf '%s\n' true
	else
		printf '%s\n' false
	fi
}

runtime_capability_reason() {
	case "$1" in
	supports_apt)
		if supports_apt; then
			printf '%s\n' 'apt-get and dpkg-query are available'
		else
			printf '%s\n' 'apt-get or dpkg-query is missing'
		fi
		;;
	supports_systemd)
		if supports_systemd; then
			printf '%s\n' 'systemctl and a systemd runtime are available'
		else
			printf '%s\n' 'systemd runtime is unavailable or inactive'
		fi
		;;
	supports_docker)
		if command_exists docker; then
			printf '%s\n' 'docker command is already available'
		elif supports_apt; then
			printf '%s\n' 'docker can be installed through the APT package path'
		else
			printf '%s\n' 'docker is missing and no managed installer capability is available'
		fi
		;;
	supports_rootless)
		if supports_rootless; then
			printf '%s\n' 'non-root user has writable HOME and sudo is available'
		else
			printf '%s\n' 'rootless user setup prerequisites are not available'
		fi
		;;
	*)
		printf '%s\n' 'unknown capability'
		return 2
		;;
	esac
}

runtime_capability_registry() {
	local capability
	for capability in $(runtime_capability_names); do
		printf '%s=%s reason=%s\n' "${capability}" "$(runtime_capability_status "${capability}")" "$(runtime_capability_reason "${capability}")"
	done
}

runtime_capability_json() {
	local capability
	local first=true
	printf '    {'
	for capability in $(runtime_capability_names); do
		if [[ "${first}" == "true" ]]; then
			first=false
		else
			printf ','
		fi
		printf '\n      "%s": %s' "${capability}" "$(runtime_capability_status "${capability}")"
	done
	printf '\n    }'
}

platform_context_summary() {
	local runtime
	local wsl_status='native-linux'

	if platform_is_wsl; then
		wsl_status='wsl'
	fi

	runtime="$(platform_container_runtime)"
	printf 'os=%s arch=%s normalized_arch=%s runtime=%s environment=%s capabilities=[%s]\n' \
		"$(platform_pretty_name)" \
		"$(platform_arch)" \
		"$(platform_arch_normalized)" \
		"${runtime}" \
		"${wsl_status}" \
		"$(runtime_capability_registry | tr '\n' ';' | sed 's/;$//')"
}

platform_validate() {
	local runtime

	log_info "Platform context: $(platform_context_summary)"

	if ! platform_is_supported_arch; then
		log_error "Unsupported architecture: $(platform_arch). Supported architectures: x86_64/amd64 and aarch64/arm64."
		return 1
	fi

	if ! supports_apt; then
		log_error "Unsupported package runtime. zcodex currently requires the APT capability (apt-get and dpkg-query)."
		return 1
	fi

	if platform_is_supported_ubuntu; then
		log_success "Ubuntu-first platform detected: $(platform_pretty_name)."
	else
		log_warn "$(platform_pretty_name) is not a primary zcodex target. Continuing because required capabilities are present; package behavior is best-effort and unsupported."
	fi

	if platform_is_wsl; then
		log_warn "WSL environment detected; Docker and shell integration behavior may differ from native Linux."
	fi

	runtime="$(platform_container_runtime)"
	if [[ "${runtime}" != "none" ]]; then
		log_warn "Container runtime detected (${runtime}); service management and Docker setup may be limited."
	fi
}
