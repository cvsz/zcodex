#!/usr/bin/env bash
# Shared Bats helpers for deterministic, CI-safe test execution.

zcodex_test_setup() {
	export REPO_ROOT="${BATS_TEST_DIRNAME}/.."
	export LC_ALL="${LC_ALL:-C.UTF-8}"
	export LANG="${LANG:-C.UTF-8}"
	export TZ="${TZ:-UTC}"
	umask 022

	local tmp_parent="${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}}"
	mkdir -p "${tmp_parent}"
	ZCODEX_TEST_WORKDIR="$(mktemp -d "${tmp_parent%/}/zcodex.${BATS_TEST_NUMBER:-0}.XXXXXX")"
	export ZCODEX_TEST_WORKDIR
	export TMPDIR="${ZCODEX_TEST_WORKDIR}/tmp"
	export HOME="${ZCODEX_TEST_WORKDIR}/home"
	export XDG_CACHE_HOME="${ZCODEX_TEST_WORKDIR}/cache"
	export XDG_CONFIG_HOME="${ZCODEX_TEST_WORKDIR}/config"
	export XDG_DATA_HOME="${ZCODEX_TEST_WORKDIR}/data"
	export ZCODEX_BACKUP_DIR="${ZCODEX_TEST_WORKDIR}/backup"
	export ZCODEX_STATE_HOME="${ZCODEX_TEST_WORKDIR}/state-home"
	export ZCODEX_STATE_DIR="${ZCODEX_STATE_HOME}/state"
	export ZCODEX_TMP_DIR="${ZCODEX_TEST_WORKDIR}/runtime-tmp"
	export ZCODEX_INSTALL_ID="bats-${BATS_TEST_NUMBER:-0}"
	mkdir -p "${TMPDIR}" "${HOME}" "${XDG_CACHE_HOME}" "${XDG_CONFIG_HOME}" "${XDG_DATA_HOME}"
}

zcodex_test_teardown() {
	if [[ -n "${ZCODEX_TEST_WORKDIR:-}" && -d "${ZCODEX_TEST_WORKDIR}" ]]; then
		rm -rf "${ZCODEX_TEST_WORKDIR}"
	fi
}

zcodex_tmpdir() {
	mktemp -d "${TMPDIR%/}/${1:-tmp}.XXXXXX"
}

zcodex_tmpfile() {
	mktemp "${TMPDIR%/}/${1:-tmp}.XXXXXX"
}
