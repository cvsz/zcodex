#!/usr/bin/env bash
# Deterministic version pins for zcodex-managed runtime dependencies.

: "${ZCODEX_INSTALLER_VERSION:=0.3.0}"
: "${ZCODEX_NODEJS_VERSION:=22}"
: "${ZCODEX_NODEJS_PACKAGE_VERSION:=}"
: "${ZCODEX_DOCKER_PACKAGE_VERSION:=}"
: "${ZCODEX_DOCKER_COMPOSE_PACKAGE_VERSION:=}"
: "${ZCODEX_CODEX_CLI_VERSION:=0.129.0}"

pins_validate_semver_or_major() {
	local value="$1"
	[[ "${value}" =~ ^[0-9]+([.][0-9]+){0,2}([+-][A-Za-z0-9._-]+)?$ ]]
}

pins_validate_apt_version() {
	local value="$1"
	[[ "${value}" =~ ^[-A-Za-z0-9:.+_~]+$ ]]
}

pins_validate_optional_apt_version() {
	local name="$1"
	local value="$2"
	if [[ -n "${value}" ]] && ! pins_validate_apt_version "${value}"; then
		log_error "Invalid ${name} apt package pin: ${value}"
		return 1
	fi
}

pins_validate() {
	if ! pins_validate_semver_or_major "${ZCODEX_NODEJS_VERSION}"; then
		log_error "Invalid ZCODEX_NODEJS_VERSION pin: ${ZCODEX_NODEJS_VERSION}"
		return 1
	fi

	if ! pins_validate_semver_or_major "${ZCODEX_CODEX_CLI_VERSION}"; then
		log_error "Invalid ZCODEX_CODEX_CLI_VERSION pin: ${ZCODEX_CODEX_CLI_VERSION}"
		return 1
	fi

	pins_validate_optional_apt_version ZCODEX_NODEJS_PACKAGE_VERSION "${ZCODEX_NODEJS_PACKAGE_VERSION}" || return 1
	pins_validate_optional_apt_version ZCODEX_DOCKER_PACKAGE_VERSION "${ZCODEX_DOCKER_PACKAGE_VERSION}" || return 1
	pins_validate_optional_apt_version ZCODEX_DOCKER_COMPOSE_PACKAGE_VERSION "${ZCODEX_DOCKER_COMPOSE_PACKAGE_VERSION}" || return 1
}

pins_summary() {
	cat <<PINS
Version pins:
  installer=${ZCODEX_INSTALLER_VERSION}
  nodejs=${ZCODEX_NODEJS_VERSION}${ZCODEX_NODEJS_PACKAGE_VERSION:+ apt=${ZCODEX_NODEJS_PACKAGE_VERSION}}
  docker=${ZCODEX_DOCKER_PACKAGE_VERSION:-ubuntu-candidate}
  docker-compose-plugin=${ZCODEX_DOCKER_COMPOSE_PACKAGE_VERSION:-ubuntu-candidate}
  codex-cli=${ZCODEX_CODEX_CLI_VERSION}
PINS
}
