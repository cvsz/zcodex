#!/usr/bin/env bash
# Backward-compatible entry point for release tag validation.
set -euo pipefail

export LC_ALL=C.UTF-8
export LANG=C.UTF-8
export TZ=UTC
umask 022

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/validate-release.sh" "$@"
