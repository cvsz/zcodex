#!/usr/bin/env bash
# Lightweight environment validation for CI and preflight checks.

set -Eeuo pipefail

export LC_ALL=C.UTF-8
export LANG=C.UTF-8
export TZ=UTC
umask 022

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
LOG_FILE="${LOG_FILE:-/tmp/zcodex-validate.log}"
CI_MODE="${CI_MODE:-${CI:-false}}"

# shellcheck source=scripts/lib/logging.sh
. "${LIB_DIR}/logging.sh"
# shellcheck source=scripts/lib/platform.sh
. "${LIB_DIR}/platform.sh"

main() {
	logging_init
	platform_validate
	log_success "Environment is supported."
}

main "$@"
