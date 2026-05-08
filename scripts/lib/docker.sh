#!/usr/bin/env bash
# Docker installation helpers.

docker_install_managed() {
	local packages=(docker.io docker-compose-plugin)

	if command_exists docker; then
		log_success "Docker is already installed."
		return 0
	fi

	if [[ -n "${ZCODEX_DOCKER_PACKAGE_VERSION}" ]]; then
		packages[0]="docker.io=${ZCODEX_DOCKER_PACKAGE_VERSION}"
	fi
	if [[ -n "${ZCODEX_DOCKER_COMPOSE_PACKAGE_VERSION}" ]]; then
		packages[1]="docker-compose-plugin=${ZCODEX_DOCKER_COMPOSE_PACKAGE_VERSION}"
	fi

	if ! supports_docker; then
		log_error "Docker capability is unavailable; install Docker manually or rerun with --skip-docker."
		return 1
	fi

	log_info "Installing Docker packages through the managed APT package path."
	packages_install "${packages[@]}"
	if supports_systemd; then
		sudo systemctl enable --now docker || log_warn "Docker service could not be enabled in this environment."
	else
		log_warn "Skipping Docker service enablement because systemd capability is unavailable."
	fi
}

docker_configure_user() {
	local user_name="${SUDO_USER:-${USER}}"
	if getent group docker >/dev/null 2>&1; then
		sudo usermod -aG docker "${user_name}" || log_warn "Could not add ${user_name} to docker group."
	fi
}

docker_install_ubuntu() {
	docker_install_managed "$@"
}
