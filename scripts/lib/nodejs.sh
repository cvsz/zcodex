#!/usr/bin/env bash
# Node.js installation helpers.

nodejs_installed_version() {
	command_exists node || return 1
	node --version | sed 's/^v//'
}

nodejs_version_matches_pin() {
	local installed="$1"
	case "${installed}" in
	"${ZCODEX_NODEJS_VERSION}" | "${ZCODEX_NODEJS_VERSION}."*) return 0 ;;
	*) return 1 ;;
	esac
}

nodejs_install_managed() {
	local installed_version
	installed_version="$(nodejs_installed_version 2>/dev/null || true)"
	if [[ -n "${installed_version}" ]] && nodejs_version_matches_pin "${installed_version}"; then
		log_success "Node.js v${installed_version} matches pin ${ZCODEX_NODEJS_VERSION}."
		return 0
	fi

	if ! supports_apt; then
		log_error "Node.js installation requires the APT capability."
		return 1
	fi

	log_info "Installing Node.js pin ${ZCODEX_NODEJS_VERSION} through the managed APT package path."
	if [[ -n "${ZCODEX_NODEJS_PACKAGE_VERSION}" ]]; then
		packages_install "nodejs=${ZCODEX_NODEJS_PACKAGE_VERSION}" npm
	else
		packages_install nodejs npm
	fi

	installed_version="$(nodejs_installed_version 2>/dev/null || true)"
	if [[ -z "${installed_version}" ]] || ! nodejs_version_matches_pin "${installed_version}"; then
		log_error "Installed Node.js version v${installed_version:-missing} does not satisfy pin ${ZCODEX_NODEJS_VERSION}."
		return 1
	fi
}

nodejs_install_global_packages() {
	local packages=("$@")
	if ((${#packages[@]} == 0)); then
		return 0
	fi
	retry 3 2 sudo npm install --global "${packages[@]}"
}

nodejs_install_ubuntu() {
	nodejs_install_managed "$@"
}
