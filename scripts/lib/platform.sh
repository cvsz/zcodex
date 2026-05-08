#!/usr/bin/env bash
# Platform detection and validation helpers.

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

platform_is_supported_ubuntu() {
	local os_release_file
	os_release_file="$(platform_os_release_file)"
	[[ -r "${os_release_file}" ]] || return 1
	# shellcheck disable=SC1090
	. "${os_release_file}"
	[[ "${ID:-}" == "ubuntu" ]] || return 1
	case "${VERSION_ID:-}" in
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

platform_context_summary() {
	local os_release_file
	local runtime
	local wsl_status='native-linux'
	local pretty_name='unknown Linux'
	os_release_file="$(platform_os_release_file)"

	if [[ -r "${os_release_file}" ]]; then
		# shellcheck disable=SC1090
		. "${os_release_file}"
		pretty_name="${PRETTY_NAME:-${ID:-unknown} ${VERSION_ID:-}}"
	fi

	if platform_is_wsl; then
		wsl_status='wsl'
	fi

	runtime="$(platform_container_runtime)"
	printf 'os=%s arch=%s normalized_arch=%s runtime=%s environment=%s\n' \
		"${pretty_name}" \
		"$(platform_arch)" \
		"$(platform_arch_normalized)" \
		"${runtime}" \
		"${wsl_status}"
}

platform_validate() {
	local runtime

	log_info "Platform context: $(platform_context_summary)"

	if ! platform_is_supported_ubuntu; then
		log_error "Unsupported OS. This installer supports Ubuntu 22.04 and 24.04."
		return 1
	fi

	if ! platform_is_supported_arch; then
		log_error "Unsupported architecture: $(platform_arch). Supported architectures: x86_64/amd64 and aarch64/arm64."
		return 1
	fi

	if platform_is_wsl; then
		log_warn "WSL environment detected; Docker and shell integration behavior may differ from native Ubuntu."
	fi

	runtime="$(platform_container_runtime)"
	if [[ "${runtime}" != "none" ]]; then
		log_warn "Container runtime detected (${runtime}); service management and Docker setup may be limited."
	fi
}
