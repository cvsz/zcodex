# zcodex vX.Y.Z

## Highlights

- Short user-facing summary of the release.
- Mention installer, security, release, or documentation changes that affect users.

## Upgrade guidance

Most users can download the release archive or update their clone and rerun validation:

```bash
make validate
bash scripts/doctor.sh
```

## Verification

Download `SHA256SUMS` and the release archive, then run:

```bash
sha256sum -c SHA256SUMS
```

## Artifacts

- `zcodex-vX.Y.Z.tar.gz`
- `SHA256SUMS`
- `SIGNING_INSTRUCTIONS.md`

## Known limitations

- Ubuntu 22.04 LTS and 24.04 LTS are the primary supported targets.
- WSL and container environments are detected and handled best-effort according to runtime capabilities.
