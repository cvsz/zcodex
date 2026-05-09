#!/usr/bin/env bash
# Deterministic Bats runtime harness and fixture injection helpers.

normalize_locale() {
	export LC_ALL=C.UTF-8
	export LANG=C.UTF-8
	export TZ=UTC
	umask 022
}

reset_path() {
	export ZCODEX_TEST_SYSTEM_PATH="${ZCODEX_TEST_SYSTEM_PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}"
	export PATH="${ZCODEX_TEST_SYSTEM_PATH}"
}

isolate_tmpdir() {
	local tmp_parent="${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}}"
	mkdir -p "${tmp_parent}"
	ZCODEX_TEST_WORKDIR="$(mktemp -d "${tmp_parent%/}/zcodex.${BATS_TEST_NUMBER:-0}.XXXXXX")"
	export ZCODEX_TEST_WORKDIR
	export TMPDIR="${ZCODEX_TEST_WORKDIR}/tmp"
	export ZCODEX_TMP_DIR="${ZCODEX_TEST_WORKDIR}/runtime-tmp"
	mkdir -p "${TMPDIR}" "${ZCODEX_TMP_DIR}"
}

isolate_home() {
	: "${ZCODEX_TEST_WORKDIR:?isolate_tmpdir must run before isolate_home}"
	export HOME="${ZCODEX_TEST_WORKDIR}/home"
	export XDG_CACHE_HOME="${ZCODEX_TEST_WORKDIR}/xdg-cache"
	export XDG_CONFIG_HOME="${ZCODEX_TEST_WORKDIR}/xdg-config"
	export XDG_DATA_HOME="${ZCODEX_TEST_WORKDIR}/xdg-data"
	export XDG_STATE_HOME="${ZCODEX_TEST_WORKDIR}/xdg-state"
	export npm_config_cache="${ZCODEX_TEST_WORKDIR}/npm-cache"
	export NPM_CONFIG_CACHE="${npm_config_cache}"
	export npm_config_prefix="${ZCODEX_TEST_WORKDIR}/npm-prefix"
	export NPM_CONFIG_PREFIX="${npm_config_prefix}"
	export ZCODEX_BACKUP_DIR="${ZCODEX_TEST_WORKDIR}/backup"
	export ZCODEX_STATE_HOME="${ZCODEX_TEST_WORKDIR}/state-home"
	export ZCODEX_STATE_DIR="${ZCODEX_STATE_HOME}/state"
	mkdir -p "${HOME}" "${XDG_CACHE_HOME}" "${XDG_CONFIG_HOME}" "${XDG_DATA_HOME}" "${XDG_STATE_HOME}" "${npm_config_cache}" "${npm_config_prefix}" "${ZCODEX_STATE_DIR}"
}

setup_test_environment() {
	export REPO_ROOT="${BATS_TEST_DIRNAME}/.."
	normalize_locale
	reset_path
	isolate_tmpdir
	isolate_home
	export ZCODEX_INSTALL_ID="bats-${BATS_TEST_NUMBER:-0}"
	# Keep release-log tests deterministic even when the caller exports
	# production-oriented log overrides into the Bats environment.
	unset ZCODEX_RELEASE_LOG LOG_FILE
	reset_path
	inject_runtime_fixture clean-system
}

teardown_test_environment() {
	if [[ -n "${ZCODEX_TEST_WORKDIR:-}" && -d "${ZCODEX_TEST_WORKDIR}" ]]; then
		rm -rf "${ZCODEX_TEST_WORKDIR}"
	fi
	reset_path
}

runtime_fixture_root() {
	printf '%s/tests/runtime-fixtures/%s\n' "${REPO_ROOT}" "$1"
}

runtime_fixture_hostless_bin() {
	: "${ZCODEX_TEST_WORKDIR:?setup_test_environment must run before hostless fixture injection}"

	local shim_dir command_path command_name
	shim_dir="${ZCODEX_TEST_WORKDIR}/hostless-bin"
	mkdir -p "${shim_dir}"

	for command_name in bash mkdir mktemp rm; do
		command_path="$(PATH="${ZCODEX_TEST_SYSTEM_PATH}" command -v "${command_name}")"
		[[ -n "${command_path}" ]] || {
			printf 'missing required hostless shim command: %s\n' "${command_name}" >&2
			return 1
		}
		ln -sf "${command_path}" "${shim_dir}/${command_name}"
	done

	printf '%s\n' "${shim_dir}"
}

runtime_fixture_inject() {
	local fixture="$1"
	local fixture_dir fixture_path
	fixture_dir="$(runtime_fixture_root "${fixture}")"
	[[ -d "${fixture_dir}" ]] || {
		printf 'missing runtime fixture: %s\n' "${fixture}" >&2
		return 1
	}
	export ZCODEX_RUNTIME_FIXTURE="${fixture}"
	export ZCODEX_RUNTIME_FIXTURE_DIR="${fixture_dir}"
	fixture_path="${fixture_dir}/bin:${ZCODEX_TEST_SYSTEM_PATH}"
	if [[ "${fixture}" == "missing-runtime" ]]; then
		fixture_path="${fixture_dir}/bin:$(runtime_fixture_hostless_bin)"
	fi
	export PATH="${fixture_path}"
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

inject_runtime_fixture() {
	runtime_fixture_inject "$@"
}
