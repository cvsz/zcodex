# Production Security Hardening Baseline

This repository enforces secure-by-default behavior for CI and runtime bootstrap scripts.

## Controls Implemented

- **Least privilege / attack-surface reduction**: workflows use minimum `permissions` and pinned actions.
- **Secret scanning**: gitleaks in CI and pre-commit hooks.
- **SAST**: CodeQL and Trivy config scanning in `.github/workflows/security.yml`.
- **DAST**: Add OWASP ZAP baseline in deployment pipeline for internet-exposed services.
- **Environment validation**: `scripts/validate-environment.sh` and `scripts/security-baseline.sh`.
- **Structured + audit logging**: enforced through `ZCODEX_LOG_FORMAT=json` and `ZCODEX_AUDIT_LOG_ENABLED=true` baseline checks.
- **Runtime hardening defaults**: strict `PATH` analysis, hardened `umask 027`, and absolute `TMPDIR` requirements.
- **Secret isolation**: `ZCODEX_REQUIRED_SECRETS` gate prevents partial bootstraps with missing secrets.
- **Health endpoint policy**: every deployed service should expose `/healthz` and `/readyz` unauthenticated probes, and keep audit events for failures.
- **Graceful shutdown policy**: services must trap SIGTERM, drain in-flight requests, and flush logs/metrics before exit.
- **Observability baseline**: metrics, traces, and alerting are required in production deployment templates.

## OWASP ASVS Alignment (high-level)

- **V1, V2**: architecture and authentication policies documented in `SECURITY_ARCHITECTURE.md` and `SECURITY.md`.
- **V5**: validation and sanitization via strict shell guards (`set -Eeuo pipefail`) and environment checks.
- **V7**: output and logging integrity through JSON logging controls.
- **V9**: secure communication and dependency controls via CI security scans.
- **V14**: configuration hardening through preflight validation and hardened defaults.

## Production Deployment Safety Gates

1. Run `scripts/validate-environment.sh`.
2. Run `scripts/security-baseline.sh` with production environment variables.
3. Run CI `security` workflow (CodeQL, Trivy, gitleaks).
4. Run pre-commit hooks locally before merge.
5. Require signed commits and signed tags on protected branches.
