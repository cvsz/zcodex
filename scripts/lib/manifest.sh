#!/usr/bin/env bash
# Machine-readable installation manifest helpers.

: "${ZCODEX_STATE_HOME:=${HOME}/.local/share/zcodex}"
: "${ZCODEX_MANIFEST_FILE:=${ZCODEX_STATE_HOME}/manifest.json}"

manifest_json_escape() {
	local value="$1"
	value="${value//\\/\\\\}"
	value="${value//\"/\\\"}"
	value="${value//$'\n'/\\n}"
	value="${value//$'\r'/\\r}"
	value="${value//$'\t'/\\t}"
	printf '%s' "${value}"
}

manifest_json_string() {
	local value="$1"
	printf '"%s"' "$(manifest_json_escape "${value}")"
}

manifest_json_nullable() {
	local value="${1:-}"
	if [[ -z "${value}" ]]; then
		printf 'null'
	else
		manifest_json_string "${value}"
	fi
}

manifest_command_version() {
	local command_name="$1"
	shift
	command_exists "${command_name}" || return 1
	"${command_name}" "$@" 2>/dev/null | head -n 1
}

manifest_dpkg_version() {
	local package_name="$1"
	dpkg-query -W -f='${Version}' "${package_name}" 2>/dev/null || true
}

manifest_sha256_for_command() {
	local command_name="$1"
	local command_path
	command_path="$(command -v "${command_name}" 2>/dev/null || true)"
	[[ -n "${command_path}" && -r "${command_path}" ]] || return 0
	sha256sum "${command_path}" 2>/dev/null | awk '{ print $1 }'
}

manifest_platform_json() {
	local os_release_file
	local pretty_name='unknown Linux'
	local os_id='unknown'
	local version_id='unknown'
	os_release_file="$(platform_os_release_file)"
	if [[ -r "${os_release_file}" ]]; then
		# shellcheck disable=SC1090
		. "${os_release_file}"
		pretty_name="${PRETTY_NAME:-${ID:-unknown} ${VERSION_ID:-unknown}}"
		os_id="${ID:-unknown}"
		version_id="${VERSION_ID:-unknown}"
	fi
	cat <<JSON
  "platform": {
    "os": $(manifest_json_string "${pretty_name}"),
    "id": $(manifest_json_string "${os_id}"),
    "version_id": $(manifest_json_string "${version_id}"),
    "arch": $(manifest_json_string "$(platform_arch)"),
    "normalized_arch": $(manifest_json_string "$(platform_arch_normalized)"),
    "container_runtime": $(manifest_json_string "$(platform_container_runtime)"),
    "capabilities":
$(runtime_capability_json)
  }
JSON
}

manifest_component_json() {
	local name="$1"
	local desired_version="$2"
	local installed_version="$3"
	local status="$4"
	local sha256="${5:-}"
	cat <<JSON
    {
      "name": $(manifest_json_string "${name}"),
      "desired_version": $(manifest_json_nullable "${desired_version}"),
      "installed_version": $(manifest_json_nullable "${installed_version}"),
      "status": $(manifest_json_string "${status}"),
      "sha256": $(manifest_json_nullable "${sha256}")
    }
JSON
}

manifest_component_status() {
	local installed_version="$1"
	if [[ -n "${installed_version}" ]]; then
		printf '%s\n' installed
	else
		printf '%s\n' missing
	fi
}

manifest_write() {
	local status="$1"
	local node_version npm_version docker_version compose_version codex_version
	local node_sha npm_sha docker_sha codex_sha manifest_sha
	local written_at current_phase current_status install_timestamp

	install -d -m 700 "$(dirname "${ZCODEX_MANIFEST_FILE}")"
	written_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	install_timestamp="${ZCODEX_INSTALL_TIMESTAMP:-${written_at}}"
	current_phase="$(state_current_phase 2>/dev/null || printf '%s' UNKNOWN)"
	current_status="$(state_status 2>/dev/null || printf '%s' "${status}")"
	node_version="$(manifest_command_version node --version || true)"
	npm_version="$(manifest_command_version npm --version || true)"
	docker_version="$(manifest_command_version docker --version || true)"
	compose_version="$(manifest_command_version docker compose version || true)"
	codex_version="$(manifest_command_version codex --version || true)"
	node_sha="$(manifest_sha256_for_command node || true)"
	npm_sha="$(manifest_sha256_for_command npm || true)"
	docker_sha="$(manifest_sha256_for_command docker || true)"
	codex_sha="$(manifest_sha256_for_command codex || true)"
	manifest_sha="$(printf '%s|%s|%s|%s|%s|%s' "${ZCODEX_INSTALLER_VERSION}" "${ZCODEX_NODEJS_VERSION}" "${ZCODEX_DOCKER_PACKAGE_VERSION:-ubuntu-candidate}" "${ZCODEX_CODEX_CLI_VERSION}" "$(platform_arch_normalized)" "${current_phase}" | sha256sum | awk '{ print $1 }')"

	cat >"${ZCODEX_MANIFEST_FILE}.tmp" <<JSON
{
  "schema_version": 1,
  "installer_version": $(manifest_json_string "${ZCODEX_INSTALLER_VERSION}"),
  "node_version": $(manifest_json_nullable "${node_version}"),
  "docker_version": $(manifest_json_nullable "${docker_version}"),
  "codex_version": $(manifest_json_nullable "${codex_version}"),
  "install_timestamp": $(manifest_json_string "${install_timestamp}"),
  "platform_info": {
    "os_release": $(manifest_json_string "$(platform_os_release_file)"),
$(manifest_platform_json | sed '1d;$d')
  },
  "architecture": $(manifest_json_string "$(platform_arch_normalized)"),
  "install_state": {
    "phase": $(manifest_json_string "${current_phase}"),
    "status": $(manifest_json_string "${current_status}"),
    "install_id": $(manifest_json_string "${ZCODEX_INSTALL_ID:-unknown}"),
    "state_dir": $(manifest_json_string "${ZCODEX_STATE_DIR}")
  },
  "verification_hashes": {
    "manifest_inputs": $(manifest_json_string "${manifest_sha}"),
    "node": $(manifest_json_nullable "${node_sha}"),
    "npm": $(manifest_json_nullable "${npm_sha}"),
    "docker": $(manifest_json_nullable "${docker_sha}"),
    "codex": $(manifest_json_nullable "${codex_sha}")
  },
  "installer": {
    "name": "zcodex",
    "version": $(manifest_json_string "${ZCODEX_INSTALLER_VERSION}"),
    "install_id": $(manifest_json_string "${ZCODEX_INSTALL_ID:-unknown}"),
    "written_at": $(manifest_json_string "${written_at}")
  },
$(manifest_platform_json),
  "state": {
    "phase": $(manifest_json_string "${current_phase}"),
    "status": $(manifest_json_string "${status}")
  },
  "components": [
$(manifest_component_json "nodejs" "${ZCODEX_NODEJS_VERSION}" "${node_version}" "$(manifest_component_status "${node_version}")" "${node_sha}"),
$(manifest_component_json "npm" "system" "${npm_version}" "$(manifest_component_status "${npm_version}")" "${npm_sha}"),
$(manifest_component_json "docker" "${ZCODEX_DOCKER_PACKAGE_VERSION:-ubuntu-candidate}" "${docker_version}" "$(manifest_component_status "${docker_version}")" "${docker_sha}"),
$(manifest_component_json "docker-compose-plugin" "${ZCODEX_DOCKER_COMPOSE_PACKAGE_VERSION:-ubuntu-candidate}" "${compose_version}" "$(manifest_component_status "${compose_version}")"),
$(manifest_component_json "codex-cli" "${ZCODEX_CODEX_CLI_VERSION}" "${codex_version}" "$(manifest_component_status "${codex_version}")" "${codex_sha}")
  ],
  "packages": {
    "nodejs": $(manifest_json_nullable "$(manifest_dpkg_version nodejs)"),
    "npm": $(manifest_json_nullable "$(manifest_dpkg_version npm)"),
    "docker.io": $(manifest_json_nullable "$(manifest_dpkg_version docker.io)"),
    "docker-compose-plugin": $(manifest_json_nullable "$(manifest_dpkg_version docker-compose-plugin)")
  }
}
JSON
	chmod 600 "${ZCODEX_MANIFEST_FILE}.tmp"
	mv "${ZCODEX_MANIFEST_FILE}.tmp" "${ZCODEX_MANIFEST_FILE}"
	log_success "Wrote install manifest to ${ZCODEX_MANIFEST_FILE}."
}
