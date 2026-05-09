# SLSA Level 3 Plus Skill

Use this skill for GitHub Actions supply chain hardening.

## Purpose

Help repair and improve workflows for:

- SBOM generation
- artifact digest creation
- provenance checks
- cosign signing
- dependency review
- Semgrep and Trivy scans

## Principles

- Keep workflow changes small and reviewable.
- Build artifacts before signing or verification.
- Use least privilege workflow permissions.
- Separate build, scan, signing, and verification steps.
- Prefer deterministic artifacts and stable paths.

## Output Format

Always provide:

1. root cause
2. files changed
3. patch summary
4. security impact
5. validation plan
