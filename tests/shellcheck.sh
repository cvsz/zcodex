#!/usr/bin/env bash
set -Eeuo pipefail

mapfile -t shell_files < <(find scripts tests -type f -name '*.sh' | sort)
shellcheck "${shell_files[@]}"
