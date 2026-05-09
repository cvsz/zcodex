#!/usr/bin/env bash
# Codex CLI installation and configuration helpers.

codex_installed_version() {
	command_exists codex || return 1
	codex --version 2>/dev/null | awk '{ print $NF; exit }'
}

codex_install_cli() {
	local installed_version
	installed_version="$(codex_installed_version 2>/dev/null || true)"
	if [[ "${installed_version}" == "${ZCODEX_CODEX_CLI_VERSION}" ]]; then
		log_success "Codex CLI ${installed_version} matches pin ${ZCODEX_CODEX_CLI_VERSION}."
		return 0
	fi

	log_info "Installing @openai/codex@${ZCODEX_CODEX_CLI_VERSION} with npm."
	nodejs_install_global_packages "@openai/codex@${ZCODEX_CODEX_CLI_VERSION}"

	installed_version="$(codex_installed_version 2>/dev/null || true)"
	if [[ -n "${installed_version}" && "${installed_version}" != "${ZCODEX_CODEX_CLI_VERSION}" ]]; then
		log_warn "Codex CLI reported ${installed_version}; expected ${ZCODEX_CODEX_CLI_VERSION}."
	fi
}

codex_write_config() {
	local codex_home="${CODEX_HOME:-${HOME}/.codex}"
	install -d -m 700 "${codex_home}"
	declare -F backup_file >/dev/null && backup_file "${codex_home}/config.toml"
	cat >"${codex_home}/config.toml" <<'CONFIG'
model = "codex-1"

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
