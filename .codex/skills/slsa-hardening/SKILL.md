# SLSA Hardening Skill

Use this skill when fixing or improving GitHub Actions workflows related to SLSA, SBOM, provenance, artifact signing, dependency review, and supply-chain integrity.

## Goals

- Build deterministic and auditable CI/CD pipelines.
- Generate and verify SBOMs.
- Generate provenance and attest build artifacts.
- Use keyless signing through OIDC where appropriate.
- Preserve a PR-based governance model.

## Hard Rules

- Do not create self-modifying CI workflows.
- Do not directly merge or push to protected branches.
- Use least-privilege GitHub Actions permissions.
- Use `id-token: write` only for signing or attestation jobs.
- Ensure artifacts are created before signing or provenance verification.
- Keep build, scan, signing, and verification stages clearly separated.

## Required Checks

- Dependency review before build.
- Deterministic artifact creation.
- SHA256 digest generation.
- SBOM generation in SPDX or CycloneDX format.
- Semgrep or equivalent SAST.
- Trivy or equivalent vulnerability scan.
- Provenance verification when artifacts are present.

## Output Format

Always return:

1. Root cause
2. Files changed
3. Security impact
4. Minimal patch or workflow content
5. Validation plan
