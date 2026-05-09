#!/usr/bin/env bash
set -Eeuo pipefail

mapfile -d '' -t shell_files < <({
	printf '%s\0' codex.sh
	find scripts tests -type f -name '*.sh' -print0
} | sort -z)
shellcheck "${shell_files[@]}"
