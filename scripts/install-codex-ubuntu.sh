#!/usr/bin/env bash
# zcodex Ubuntu installer entry point.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
SCRIPT_NAME="$(basename "$0")"
LOG_FILE="${LOG_FILE:-/tmp/zcodex-install.log}"

# shellcheck source=scripts/lib/runtime.sh
. "${LIB_DIR}/runtime.sh"

trap installer_cleanup EXIT
installer_run "$@"
