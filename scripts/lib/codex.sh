#!/usr/bin/env bash
# Codex CLI installation and configuration helpers.

codex_install_cli() {
	if command_exists codex; then
		log_success "Codex CLI is already installed."
		return 0
	fi

	log_info "Installing @openai/codex with npm."
	nodejs_install_global_packages @openai/codex
}

codex_write_config() {
	local codex_home="${CODEX_HOME:-${HOME}/.codex}"
	install -d -m 700 "${codex_home}"
	declare -F backup_file >/dev/null && backup_file "${codex_home}/config.toml"
	cat >"${codex_home}/config.toml" <<'CONFIG'
model = "gpt-5-codex"

approval-policy = "on-request"
sandbox-mode = "workspace-write"
CONFIG
	chmod 600 "${codex_home}/config.toml"
	log_success "Wrote ${codex_home}/config.toml."
}

codex_validate_cli() {
	command_exists codex || return 1
	codex --version >/dev/null 2>&1 || return 1
}
