#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <patch-file>" >&2
  exit 64
fi

patch_file="$1"

if [[ ! -f "$patch_file" ]]; then
  echo "Patch file not found: $patch_file" >&2
  exit 66
fi

git apply --check "$patch_file"
echo "Patch validation passed: $patch_file"
