#!/usr/bin/env bash
# Production-grade security baseline checks for zcodex automation hosts.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"

# shellcheck source=scripts/lib/logging.sh
. "${LIB_DIR}/logging.sh"
# shellcheck source=scripts/lib/platform.sh
. "${LIB_DIR}/platform.sh"
# shellcheck source=scripts/lib/security.sh
. "${LIB_DIR}/security.sh"

main() {
  # shellcheck disable=SC2119
  logging_init
  platform_validate
  security_analyze_path "${PATH}" relaxed true || true

  [[ "${ZCODEX_ENVIRONMENT:-}" =~ ^(prod|staging|dev|ci)$ ]] || { log_error "ZCODEX_ENVIRONMENT must be one of: prod|staging|dev|ci"; return 1; }
  [[ "${ZCODEX_LOG_FORMAT:-json}" == "json" ]] || { log_error "ZCODEX_LOG_FORMAT must be json"; return 1; }
  [[ "${ZCODEX_AUDIT_LOG_ENABLED:-true}" == "true" ]] || { log_error "Audit logging must stay enabled"; return 1; }

  if [[ -n "${ZCODEX_REQUIRED_SECRETS:-}" ]]; then
    IFS=',' read -r -a required <<<"${ZCODEX_REQUIRED_SECRETS}"
    for key in "${required[@]}"; do
      [[ -n "${!key:-}" ]] || { log_error "Required secret is missing: ${key}"; return 1; }
    done
  fi

  log_success "Security baseline checks passed."
}

main "$@"
