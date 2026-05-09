#!/usr/bin/env bash
# Install local maintenance tools used by this repository.

set -Eeuo pipefail

export LC_ALL=C.UTF-8
export LANG=C.UTF-8
export TZ=UTC
umask 022

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
LOG_FILE="${LOG_FILE:-/tmp/zcodex-maintenance.log}"
CI_MODE="${CI_MODE:-${CI:-false}}"

# shellcheck source=scripts/lib/logging.sh
. "${LIB_DIR}/logging.sh"
# shellcheck source=scripts/lib/retry.sh
. "${LIB_DIR}/retry.sh"
# shellcheck source=scripts/lib/platform.sh
. "${LIB_DIR}/platform.sh"
# shellcheck source=scripts/lib/packages.sh
. "${LIB_DIR}/packages.sh"

main() {
	# shellcheck disable=SC2119
	logging_init
	platform_validate
	packages_update
	packages_install shellcheck shfmt bats gitleaks
	log_success "Maintenance tools installed."
}

main "$@"
