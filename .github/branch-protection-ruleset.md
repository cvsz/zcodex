# Branch protection baseline (main)

Apply these repository rules to `main`:

- Require pull request before merging.
- Require approvals: **1+** (CODEOWNERS recommended).
- Dismiss stale approvals on new commits.
- Require conversation resolution before merge.
- Require status checks to pass:
  - `ci / bats / ubuntu-24.04 / amd64`
  - `ci / release-reproducibility`
  - `security / codeql`
  - `security / secret-scanning`
  - `supply-chain / sbom-and-provenance`
- Require signed commits.
- Require linear history.
- Restrict force-pushes and branch deletion.

This baseline enforces least privilege and prevents CI/workflow bypass on protected branches.
