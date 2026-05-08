#!/usr/bin/env bash
# Retry a command with exponential backoff.

retry() {
	local retries="$1"
	local delay="$2"
	shift 2

	local cmd=("$@")
	local attempt=1

	until "${cmd[@]}"; do
		local exit_code=$?

		if ((attempt >= retries)); then
			return "${exit_code}"
		fi

		sleep "${delay}"

		attempt=$((attempt + 1))
		delay=$((delay * 2))
	done
}
