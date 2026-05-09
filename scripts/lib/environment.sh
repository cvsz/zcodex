#!/usr/bin/env bash
# Deterministic process environment helpers.

: "${ZCODEX_DETERMINISTIC_LC_ALL:=C.UTF-8}"
: "${ZCODEX_DETERMINISTIC_LANG:=C.UTF-8}"
: "${ZCODEX_DETERMINISTIC_TZ:=UTC}"

zcodex_normalize_environment() {
	export LC_ALL="${ZCODEX_DETERMINISTIC_LC_ALL}"
	export LANG="${ZCODEX_DETERMINISTIC_LANG}"
	export TZ="${ZCODEX_DETERMINISTIC_TZ}"
	umask 022
}

zcodex_sort() {
	LC_ALL=C sort "$@"
}

zcodex_find_files_sorted() {
	local root="${1:-.}"
	shift || true
	find "${root}" "$@" -type f -print | LC_ALL=C sort
}

zcodex_jq_stable() {
	jq -S "$@"
}

zcodex_utc_now() {
	if [[ -n "${ZCODEX_FIXED_TIMESTAMP:-}" ]]; then
		printf '%s\n' "${ZCODEX_FIXED_TIMESTAMP}"
	else
		date -u +%Y-%m-%dT%H:%M:%SZ
	fi
}

zcodex_epoch_now() {
	if [[ -n "${ZCODEX_FIXED_EPOCH:-}" ]]; then
		printf '%s\n' "${ZCODEX_FIXED_EPOCH}"
	else
		date -u +%s
	fi
}

zcodex_normalize_environment
