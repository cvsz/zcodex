# CI/CD Migration Notes

## Scope audited
- GitHub Actions workflows under `.github/workflows`.
- Shell-based release, verification, diagnostics, and deployment-adjacent scripts in `scripts/`.

No Dockerfiles, docker-compose files, Kubernetes manifests, Helm charts, or Terraform files were found in this repository snapshot.

## Key repairs made
1. Added a dedicated `security` workflow with:
   - CodeQL analysis.
   - Dependency review for pull requests.
   - Secret scanning (Gitleaks) with SARIF upload.
   - Trivy filesystem scanning with SARIF upload.
2. Hardened concurrency groups to be workflow-specific (avoid cross-workflow cancellation collisions).
3. Extended supply-chain workflow with explicit summary output and provenance-related checks.

## Branch protection rollout (manual, repo-admin required)
Apply branch protection/rulesets for `main` in GitHub settings (or via API), requiring:
- Passing checks: `ci`, `e2e`, `security`, `supply-chain`, `release-validate`.
- Require pull request reviews.
- Require up-to-date branches.
- Require signed commits (if organizationally compatible).
- Disallow force pushes and branch deletion.

## Operational notes
- Artifact attestations are produced in supply-chain workflow.
- Provenance verification is kept lightweight and workflow-local; can be expanded with `gh attestation verify` once org policies are finalized.
