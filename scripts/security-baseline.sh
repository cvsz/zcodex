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
  logging_init
  platform_validate
  security_analyze_path "${PATH}" relaxed true || true

  [[ "${ZCODEX_ENVIRONMENT:-}" =~ ^(prod|staging|dev|ci)$ ]] || log_fatal "ZCODEX_ENVIRONMENT must be one of: prod|staging|dev|ci"
  [[ "${ZCODEX_LOG_FORMAT:-json}" == "json" ]] || log_fatal "ZCODEX_LOG_FORMAT must be json"
  [[ "${ZCODEX_AUDIT_LOG_ENABLED:-true}" == "true" ]] || log_fatal "Audit logging must stay enabled"

  if [[ -n "${ZCODEX_REQUIRED_SECRETS:-}" ]]; then
    IFS=',' read -r -a required <<<"${ZCODEX_REQUIRED_SECRETS}"
    for key in "${required[@]}"; do
      [[ -n "${!key:-}" ]] || log_fatal "Required secret is missing: ${key}"
    done
  fi

  log_success "Security baseline checks passed."
}

main "$@"
