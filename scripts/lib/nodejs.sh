#!/usr/bin/env bash
# Node.js installation helpers.

nodejs_install_ubuntu() {
	if command_exists node && node --version | grep -Eq '^v(20|22|24)\.'; then
		log_success "Node.js $(node --version) is already installed."
		return 0
	fi

	log_info "Installing Node.js from Ubuntu repositories."
	packages_install nodejs npm
}

nodejs_install_global_packages() {
	local packages=("$@")
	if ((${#packages[@]} == 0)); then
		return 0
	fi
	retry 3 2 sudo npm install --global "${packages[@]}"
}
