#!/usr/bin/env bash
# APT package helpers.

packages_update() {
	retry 3 2 sudo apt-get update
}

packages_install() {
	local packages=("$@")
	if ((${#packages[@]} == 0)); then
		return 0
	fi
	retry 3 2 sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y \
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
