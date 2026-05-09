# Workflow Optimization Report

## Findings
- **Concurrency collision risk:** multiple workflows shared `doctor-${ref}` group; runs could cancel each other unexpectedly.
- **Security visibility gap:** no dedicated CodeQL or dependency review workflow.
- **SARIF aggregation gap:** security scanners existed but lacked consistent SARIF upload coverage.

## Remediations
- Introduced workflow-specific concurrency group keys:
  - `ci-${workflow}-${ref}`
  - `e2e-${workflow}-${ref}`
  - `release-${workflow}-${ref}`
  - `release-validate-${workflow}-${ref}`
  - `ci-self-healing-${workflow}-${ref}`
  - `supply-chain-${workflow}-${ref}`
- Added `.github/workflows/security.yml` to centralize:
  - CodeQL
  - dependency-review
  - gitleaks SARIF upload
  - trivy SARIF upload
- Added workflow summary outputs for supply-chain and CI security visibility.

## Risk posture improvements
- Better least-privilege isolation by job-scoped permissions in security jobs.
- Improved PR gating for supply chain and dependency changes.
- Better auditable output through SARIF and step summaries.

## Remaining recommendations
- Enable GitHub Advanced Security features at repo/org level (if not already enabled).
- Enforce branch protection/rulesets to require new security checks.
- Add deploy-time health checks and rollback automation when deployment targets are introduced.
