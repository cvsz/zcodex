#!/usr/bin/env bash
set -Eeuo pipefail

export LC_ALL=C.UTF-8
export LANG=C.UTF-8
export TZ=UTC

mapfile -d '' -t shell_files < <({
	printf '%s\0' codex.sh reproducibility_validation.sh
	find scripts tests -type f \( -name '*.sh' -o -name '*.bash' \) -print0
} | LC_ALL=C sort -z)
shellcheck "${shell_files[@]}"
