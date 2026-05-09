# zcodex v0.3.0 Release Notes

Release date: 2026-05-09

## Summary

`v0.3.0` is a stabilization release focused on deterministic production release behavior, isolated E2E validation, runtime fixture coverage, security hardening, and reproducible release hashes.

## Highlights

- Deterministic release archives are built from the committed Git tree with stable tar ordering, normalized ownership, fixed mtime, UTC locale, and `gzip -n` compression.
- Release verification generates `SHA256SUMS`, validates the checksum manifest, and compares repeated archive builds for hash reproducibility.
- E2E workflows isolate home, XDG, npm cache, npm prefix, temporary, and zcodex state paths from the host environment.
- Runtime fixture scenarios cover clean systems, stale runtimes, broken npm, corrupted manifests, interrupted installs, path shadowing, missing runtimes, and conflicting runtime ownership.
- Runtime ownership and PATH safety checks fail before privileged package, npm, Docker, or shell-profile mutations.
- README documentation was rewritten for production operators and maintainers.

## Compatibility

Supported production targets remain Ubuntu 22.04 LTS and Ubuntu 24.04 LTS on `amd64`/`x86_64` and `arm64`/`aarch64`. Other environments are best-effort and should use dry-run plus doctor validation before installation.

## Upgrade notes

- Use `bash scripts/doctor.sh --offline` before rerunning the installer on an existing host.
- Hosts with nvm or asdf should use `--runtime-mode existing-runtime` after activating the intended Node.js/npm runtime.
- Hosts with mixed NodeSource and distro npm ownership should normalize ownership before non-dry-run installation.
- Release operators should validate the `v0.3.0` tag with `bash scripts/validate-release.sh v0.3.0` before publishing.

## Verification commands

```bash
make validate
bash scripts/validate-release.sh v0.3.0
bash scripts/release.sh --skip-validate
bash scripts/verify-release-artifacts.sh dist
make release-reproducible
```

## Known limitations

- Release artifacts are checksum-protected but not yet signed.
- SBOM and provenance publishing are prepared in documentation but not enabled in the release workflow.
- Full E2E execution requires Docker; dry-run E2E remains available without Docker.
