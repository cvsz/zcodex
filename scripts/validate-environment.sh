#!/usr/bin/env bash
# Lightweight environment validation for CI and preflight checks.

set -Eeuo pipefail

export LC_ALL=C.UTF-8
export LANG=C.UTF-8
export TZ=UTC
umask 027

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
LOG_FILE="${LOG_FILE:-/tmp/zcodex-validate.log}"
CI_MODE="${CI_MODE:-${CI:-false}}"

# shellcheck source=scripts/lib/logging.sh
. "${LIB_DIR}/logging.sh"
# shellcheck source=scripts/lib/platform.sh
. "${LIB_DIR}/platform.sh"
# shellcheck source=scripts/lib/security.sh
. "${LIB_DIR}/security.sh"

main() {
	logging_init
	platform_validate
	security_analyze_path "${PATH}" relaxed false >/dev/null || true
	[[ "${TMPDIR:-/tmp}" == /* ]] || log_fatal "TMPDIR must be an absolute path."
	[[ -d "${TMPDIR:-/tmp}" ]] || log_fatal "TMPDIR does not exist: ${TMPDIR:-/tmp}"
	[[ "${ZCODEX_ALLOW_INSECURE_PATH:-false}" == "false" ]] || log_warn "Insecure PATH override is enabled."
	log_success "Environment is supported and hardened defaults are active."
}

main "$@"
