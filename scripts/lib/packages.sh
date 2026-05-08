#!/usr/bin/env bash
# APT package helpers.

packages_update() {
	if ! supports_apt; then
		log_error "APT capability is required for package metadata updates."
		return 1
	fi
	retry 3 2 runtime_privileged apt-get update
}

packages_install() {
	local packages=("$@")
	if ! supports_apt; then
		log_error "APT capability is required for package installation."
		return 1
	fi
	if ((${#packages[@]} == 0)); then
		return 0
	fi
	retry 3 2 runtime_privileged env DEBIAN_FRONTEND=noninteractive apt-get install -y \
		-o Dpkg::Options::=--force-confnew \
		"${packages[@]}"
}

packages_install_base() {
	packages_install \
		apt-transport-https \
		ca-certificates \
		curl \
		git \
		gnupg \
		jq \
		make \
		software-properties-common \
		unzip
}
