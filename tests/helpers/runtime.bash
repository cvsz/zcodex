#!/usr/bin/env bash
# Deterministic Bats runtime harness and fixture injection helpers.

setup_test_environment() {
	export REPO_ROOT="${BATS_TEST_DIRNAME}/.."
	export LC_ALL=C.UTF-8
	export LANG=C.UTF-8
	export TZ=UTC
	umask 022

	local tmp_parent="${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}}"
	mkdir -p "${tmp_parent}"
	ZCODEX_TEST_WORKDIR="$(mktemp -d "${tmp_parent%/}/zcodex.${BATS_TEST_NUMBER:-0}.XXXXXX")"
	export ZCODEX_TEST_WORKDIR
	export TMPDIR="${ZCODEX_TEST_WORKDIR}/tmp"
	export HOME="${ZCODEX_TEST_WORKDIR}/home"
	export XDG_CACHE_HOME="${ZCODEX_TEST_WORKDIR}/xdg-cache"
	export XDG_CONFIG_HOME="${ZCODEX_TEST_WORKDIR}/xdg-config"
	export XDG_DATA_HOME="${ZCODEX_TEST_WORKDIR}/xdg-data"
	export XDG_STATE_HOME="${ZCODEX_TEST_WORKDIR}/xdg-state"
	export ZCODEX_BACKUP_DIR="${ZCODEX_TEST_WORKDIR}/backup"
	export ZCODEX_STATE_HOME="${ZCODEX_TEST_WORKDIR}/state-home"
	export ZCODEX_STATE_DIR="${ZCODEX_STATE_HOME}/state"
	export ZCODEX_TMP_DIR="${ZCODEX_TEST_WORKDIR}/runtime-tmp"
	export ZCODEX_INSTALL_ID="bats-${BATS_TEST_NUMBER:-0}"
	export ZCODEX_TEST_SYSTEM_PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
	mkdir -p "${TMPDIR}" "${HOME}" "${XDG_CACHE_HOME}" "${XDG_CONFIG_HOME}" "${XDG_DATA_HOME}" "${XDG_STATE_HOME}" "${ZCODEX_STATE_DIR}" "${ZCODEX_TMP_DIR}"
	runtime_fixture_inject clean-system
}

teardown_test_environment() {
	if [[ -n "${ZCODEX_TEST_WORKDIR:-}" && -d "${ZCODEX_TEST_WORKDIR}" ]]; then
		rm -rf "${ZCODEX_TEST_WORKDIR}"
	fi
}

runtime_fixture_root() {
	printf '%s/tests/runtime-fixtures/%s\n' "${REPO_ROOT}" "$1"
}

runtime_fixture_inject() {
	local fixture="$1"
	local fixture_dir
	fixture_dir="$(runtime_fixture_root "${fixture}")"
	[[ -d "${fixture_dir}" ]] || {
		printf 'missing runtime fixture: %s\n' "${fixture}" >&2
		return 1
	}
	export ZCODEX_RUNTIME_FIXTURE="${fixture}"
	export ZCODEX_RUNTIME_FIXTURE_DIR="${fixture_dir}"
	export PATH="${fixture_dir}/bin:${ZCODEX_TEST_SYSTEM_PATH}"
}

runtime_fixture_write_command() {
	local fixture="$1"
	local name="$2"
	local body="$3"
	local target
	target="$(runtime_fixture_root "${fixture}")/bin/${name}"
	mkdir -p "$(dirname "${target}")"
	printf '%s\n' "${body}" >"${target}"
	chmod +x "${target}"
}

runtime_fixture_fake_ownership() {
	local fixture="$1"
	local command_name="$2"
	local owner="$3"
	mkdir -p "$(runtime_fixture_root "${fixture}")/ownership"
	printf '%s\n' "${owner}" >"$(runtime_fixture_root "${fixture}")/ownership/${command_name}.owner"
}
