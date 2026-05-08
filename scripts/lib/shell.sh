#!/usr/bin/env bash
# Shell integration helpers.

shell_append_once() {
	local file="$1"
	local marker="$2"
	local content="$3"

	install -d -m 700 "$(dirname "${file}")"
	if [[ ! -e "${file}" ]]; then
		: >"${file}"
		chmod 600 "${file}"
	fi
	if grep -Fq "${marker}" "${file}"; then
		return 0
	fi
	{
		printf '\n%s\n' "${marker}"
		printf '%s\n' "${content}"
	} >>"${file}"
}

shell_configure_codex() {
	if [[ "${CI_MODE}" == "true" ]]; then
		log_info "Skipping shell profile updates in CI mode."
		return 0
	fi

	# shellcheck disable=SC2016
	shell_append_once "${HOME}/.bashrc" "# zcodex codex cli" 'export CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"'
	log_success "Shell profile updated."
}
