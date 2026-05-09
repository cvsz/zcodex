# Release reproducibility

Date: 2026-05-09

## Contract

Release artifacts are reproducible for the same committed Git tree and release version.

## Archive rules

`scripts/release.sh` builds `zcodex-vX.Y.Z.tar.gz` with:

- `tar --sort=name`
- `tar --mtime='UTC 2025-01-01'`
- `tar --owner=0 --group=0 --numeric-owner`
- `gzip -n`
- C locale and UTC timezone

## Checksum rules

- `SHA256SUMS` is generated with `sha256sum zcodex-vX.Y.Z.tar.gz`.
- The checksum file is verified with `sha256sum -c`.
- Two independent build directories must produce byte-identical archives.

## Validation

Run:

```bash
./reproducibility_validation.sh
```

The script:

1. Removes two reproducibility output directories.
2. Builds with `scripts/build-release.sh` into each directory.
3. Verifies each `SHA256SUMS` file.
4. Compares archives with `cmp`.
5. Prints the shared SHA-256 digest.

## Exclusions

- Runtime manifests and diagnostics are host snapshots and are not release reproducibility artifacts.
- Workflows were not modified in this phase.
