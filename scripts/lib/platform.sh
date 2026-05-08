#!/usr/bin/env bash
# Platform detection and validation helpers.

command_exists() {
	command -v "$1" >/dev/null 2>&1
}

platform_arch() {
	uname -m
}

platform_is_supported_ubuntu() {
	[[ -r /etc/os-release ]] || return 1
	# shellcheck disable=SC1091
	. /etc/os-release
	[[ "${ID:-}" == "ubuntu" ]] || return 1
	case "${VERSION_ID:-}" in
	22.04 | 24.04) return 0 ;;
	*) return 1 ;;
	esac
}

platform_validate() {
	if ! platform_is_supported_ubuntu; then
		log_error "Unsupported OS. This installer supports Ubuntu 22.04 and 24.04."
		return 1
	fi

	case "$(platform_arch)" in
	x86_64 | aarch64 | arm64) ;;
	*)
		log_error "Unsupported architecture: $(platform_arch)"
		return 1
		;;
	esac
}
