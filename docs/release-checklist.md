# Release Checklist

Use this checklist before publishing a tagged release. The current prepared release is `v0.3.0` with `VERSION` set to `0.3.0`.

## v0.3.0 readiness

- [x] `README.md` rewritten with operational architecture, deterministic runtime, ownership, recovery, CI/CD, E2E, release, troubleshooting, development, contribution, and FAQ sections.
- [x] `CHANGELOG.md` contains `## v0.3.0 - 2026-05-09`.
- [x] `VERSION` contains `0.3.0` without a leading `v`.
- [x] Release tag contract documented as `v0.3.0`.
- [x] Runtime fixture coverage includes clean, stale, broken, conflicting, missing, interrupted, and path-shadowed cases.
- [x] Release documentation includes notes and a final verification report.

## Pre-release validation

Run the local validation gates from a clean working tree:

```bash
make validate
CI=true bash scripts/install-codex-ubuntu.sh --dry-run --skip-docker --skip-optional
bash scripts/validate-release.sh v0.3.0
```

Confirm no generated files, logs, secrets, local npm caches, diagnostics bundles, or `dist/` artifacts are staged.

## Release artifact build

Build and verify deterministic release artifacts:

```bash
bash scripts/release.sh
bash scripts/verify-release-artifacts.sh dist
make release-reproducible
```

Review generated files:

```bash
sed -n '1,200p' dist/RELEASE_NOTES.md
cat dist/SHA256SUMS
```

## Publish

Create and push the release tag only after validation passes:

```bash
git tag v0.3.0
git push origin v0.3.0
```

The tag-triggered release workflow validates the tag, reruns repository gates, builds the deterministic archive, verifies checksums, and publishes release assets.

## Post-release verification

- [ ] Confirm the GitHub Release includes `zcodex-v0.3.0.tar.gz`, `SHA256SUMS`, release notes, and signing preparation notes.
- [ ] Confirm checksum verification succeeds after downloading release assets.
- [ ] Confirm README workflow badges are passing on `main`.
- [ ] Confirm docs and changelog describe the published version.
- [ ] Open follow-up issues for deferred signing, SBOM, provenance, or platform-expansion work.
