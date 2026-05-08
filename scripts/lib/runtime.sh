#!/usr/bin/env bash
# Runtime library loader for zcodex entry points.

runtime_lib_dir() {
	local source_path="${BASH_SOURCE[0]}"
	cd "$(dirname "${source_path}")" && pwd
}

ZCODEX_RUNTIME_LIB_DIR="${ZCODEX_RUNTIME_LIB_DIR:-$(runtime_lib_dir)}"

# shellcheck source=scripts/lib/logging.sh
. "${ZCODEX_RUNTIME_LIB_DIR}/logging.sh"
# shellcheck source=scripts/lib/retry.sh
. "${ZCODEX_RUNTIME_LIB_DIR}/retry.sh"
# shellcheck source=scripts/lib/platform.sh
. "${ZCODEX_RUNTIME_LIB_DIR}/platform.sh"
# shellcheck source=scripts/lib/security.sh
. "${ZCODEX_RUNTIME_LIB_DIR}/security.sh"
# shellcheck source=scripts/lib/backup.sh
. "${ZCODEX_RUNTIME_LIB_DIR}/backup.sh"
# shellcheck source=scripts/lib/packages.sh
. "${ZCODEX_RUNTIME_LIB_DIR}/packages.sh"
# shellcheck source=scripts/lib/nodejs.sh
. "${ZCODEX_RUNTIME_LIB_DIR}/nodejs.sh"
# shellcheck source=scripts/lib/docker.sh
. "${ZCODEX_RUNTIME_LIB_DIR}/docker.sh"
# shellcheck source=scripts/lib/codex.sh
. "${ZCODEX_RUNTIME_LIB_DIR}/codex.sh"
# shellcheck source=scripts/lib/shell.sh
. "${ZCODEX_RUNTIME_LIB_DIR}/shell.sh"
