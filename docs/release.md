# Release Architecture

zcodex uses a Bash-first release system designed for deterministic, auditable GitHub releases.

## Release strategy

- Version source of truth: `VERSION` contains the semantic version without a leading `v`.
- Tag contract: release tags use `vX.Y.Z` and must match `VERSION`.
- Changelog contract: each release has a `CHANGELOG.md` section named `## vX.Y.Z`.
- Artifact contract: each release publishes `zcodex-vX.Y.Z.tar.gz` and `SHA256SUMS`.
- Release notes source: GitHub Release bodies are extracted from the matching changelog section.

## License verification

Every release must include the root `LICENSE` file. The current project license is MIT, and downstream redistributors should verify the canonical license text from the repository root before packaging.

```bash
test -f LICENSE
sed -n '1,25p' LICENSE
```

## Release flow

```bash
git tag v0.3.0
git push origin v0.3.0
```

The `release` workflow then:

1. Checks out the full repository history.
2. Installs ShellCheck, shfmt, and Bats.
3. Verifies the pushed tag matches `VERSION`.
4. Runs `make validate`.
5. Builds a deterministic source archive with `scripts/release.sh`.
6. Generates `SHA256SUMS`.
7. Verifies checksums.
8. Publishes a GitHub Release with the archive, checksums, and signing preparation notes.

## Deterministic artifact design

`scripts/release.sh` archives the committed Git tree with `git archive` and compresses it with `gzip -n` so the gzip header does not embed local filenames or timestamps. The archive is built from a specific Git ref, making the output reproducible for the same tree and Git implementation.

The archive intentionally contains source files rather than untracked build output. This keeps release artifacts small, auditable, and aligned with the repository state that CI validated.

## File structure

```text
VERSION                         # semantic version source of truth
CHANGELOG.md                    # release notes source
scripts/release.sh              # local/CI release artifact builder
.github/workflows/release.yml   # tag-triggered GitHub Release pipeline
dist/                           # generated locally or in CI; not committed
```

## Local release dry run

```bash
scripts/release.sh
sha256sum -c dist/SHA256SUMS
```

Use `--skip-validate` only when validation has already run in the same environment.

## Security considerations

- No `curl | bash` release path is introduced.
- Published checksums allow users to verify downloaded archives.
- Tag and `VERSION` mismatches fail before publication.
- The archive comes from a committed tree, not from mutable workspace state.
- The workflow grants only `contents: write`, which is required to publish GitHub Releases.
- Future signing hooks are documented for GPG detached signatures, cosign blob signatures, and SBOM generation once release keys and OIDC policy are finalized.
- Release maintainers verify that `LICENSE`, `CHANGELOG.md`, `VERSION`, and release notes are present before tagging.

## Future hardening

Planned additions can be enabled without changing artifact names:

- `SHA256SUMS.asc` or `SHA256SUMS.sig` for GPG/cosign signatures.
- `zcodex-vX.Y.Z.spdx.json` for SBOMs.
- Signed and protected release tags.
- SLSA provenance once the project has a stable release identity.

## Integrity gates and reproducibility checks

Release artifacts are built from a git tree with normalized ownership, ordering,
mtime, locale, timezone, and gzip headers. The release script writes
`SHA256SUMS`, immediately verifies the checksum manifest with
`scripts/verify-release-artifacts.sh`, and rebuilds the archive once to ensure
the SHA-256 hash is reproducible within the same release context.

Operators can run the same gate locally:

```bash
scripts/build-release.sh --output-dir dist
scripts/verify-release-artifacts.sh dist
make release-reproducible
```

The checksum manifest must contain exactly one deterministic `zcodex-v*.tar.gz`
entry and each digest must be lowercase SHA-256. CI uploads dry-run release
artifacts so failed checksum or reproducibility gates can be inspected without
rebuilding on a developer workstation.
