#!/usr/bin/env bash
# zcodex Ubuntu installer entry point.

set -Eeuo pipefail

ZCODEX_INSTALL_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ZCODEX_INSTALL_SCRIPT_DIR
readonly ZCODEX_INSTALL_LIB_DIR="${ZCODEX_INSTALL_SCRIPT_DIR}/lib"
ZCODEX_INSTALL_SCRIPT_NAME="$(basename "$0")"
readonly ZCODEX_INSTALL_SCRIPT_NAME
LIB_DIR="${ZCODEX_INSTALL_LIB_DIR}"
SCRIPT_NAME="${ZCODEX_INSTALL_SCRIPT_NAME}"
LOG_FILE="${LOG_FILE:-/tmp/zcodex-install.log}"

# shellcheck source=scripts/lib/runtime.sh
. "${LIB_DIR}/runtime.sh"

runtime_trap_install_exit installer_cleanup
installer_run "$@"
