#!/usr/bin/env bash
# Docker installation helpers.

docker_install_ubuntu() {
	if command_exists docker; then
		log_success "Docker is already installed."
		return 0
	fi

	log_info "Installing Docker packages from Ubuntu repositories."
	packages_install docker.io docker-compose-plugin
	sudo systemctl enable --now docker || log_warn "Docker service could not be enabled in this environment."
}

docker_configure_user() {
	local user_name="${SUDO_USER:-${USER}}"
	if getent group docker >/dev/null 2>&1; then
		sudo usermod -aG docker "${user_name}" || log_warn "Could not add ${user_name} to docker group."
	fi
}
