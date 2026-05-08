# Release Checklist

Use this checklist before publishing a tagged release.

## Pre-release

- Confirm `VERSION` contains the intended semantic version without a leading `v`.
- Confirm `CHANGELOG.md` contains a matching `## vX.Y.Z` section.
- Run local validation:

```bash
make validate
CI=true bash scripts/install-codex-ubuntu.sh --dry-run --skip-docker --skip-optional
```

- Review `README.md`, `docs/release.md`, `SECURITY.md`, and `ROADMAP.md` for stale version or support statements.
- Confirm no generated files, logs, secrets, or local state are staged.

## Build locally

```bash
scripts/release.sh
cd dist
sha256sum -c SHA256SUMS
```

Review generated release notes:

```bash
sed -n '1,200p' dist/RELEASE_NOTES.md
```

## Publish

```bash
git tag vX.Y.Z
git push origin vX.Y.Z
```

The GitHub release workflow validates the tag, runs `make validate`, builds the archive, verifies checksums, and publishes release assets.

## Post-release

- Confirm the GitHub Release exists and includes `zcodex-vX.Y.Z.tar.gz`, `SHA256SUMS`, and signing instructions.
- Confirm README badges show passing workflows on `main`.
- Confirm the release notes are readable and match the changelog.
- Open a follow-up issue for any deferred hardening work.
