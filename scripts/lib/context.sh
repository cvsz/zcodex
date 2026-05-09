#!/usr/bin/env bash
# Explicit runtime context helpers for phase-aware orchestration.

if ! declare -p ZCODEX_RUNTIME_CTX >/dev/null 2>&1; then
	declare -gA ZCODEX_RUNTIME_CTX=()
fi

runtime_ctx_valid_key() {
	[[ "$1" =~ ^[a-z][a-z0-9_]*$ ]]
}

runtime_ctx_set() {
	local key="$1"
	local value="$2"

	if ! runtime_ctx_valid_key "${key}"; then
		printf 'Invalid runtime context key: %s\n' "${key}" >&2
		return 1
	fi

	ZCODEX_RUNTIME_CTX["${key}"]="${value}"
}

runtime_ctx_get() {
	local key="$1"

	if ! runtime_ctx_valid_key "${key}"; then
		printf 'Invalid runtime context key: %s\n' "${key}" >&2
		return 1
	fi

	[[ ${ZCODEX_RUNTIME_CTX[${key}]+set} == set ]] || return 1
	printf '%s\n' "${ZCODEX_RUNTIME_CTX[${key}]}"
}

runtime_ctx_unset() {
	local key="$1"

	if ! runtime_ctx_valid_key "${key}"; then
		printf 'Invalid runtime context key: %s\n' "${key}" >&2
		return 1
	fi

	unset "ZCODEX_RUNTIME_CTX[${key}]"
}

runtime_ctx_clear() {
	ZCODEX_RUNTIME_CTX=()
}

runtime_ctx_snapshot() {
	local key
	for key in "${!ZCODEX_RUNTIME_CTX[@]}"; do
		printf '%s=%s\n' "${key}" "${ZCODEX_RUNTIME_CTX[${key}]}"
	done | LC_ALL=C sort
}
