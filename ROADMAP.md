# Roadmap

`zcodex` is intentionally small. The roadmap prioritizes installer reliability, release integrity, and operator clarity over feature breadth.

## Current focus

- Keep the Ubuntu bootstrap path stable and auditable.
- Improve diagnostics through `doctor`, manifest, and state files.
- Keep CI visible and reproducible for contributors.
- Publish clear release notes and checksums for every tagged release.

## Near term

- Add regression tests for more installer flag combinations.
- Expand manifest validation coverage.
- Add a dedicated documentation check for broken local links.
- Add issue templates for bug reports and support requests.
- Publish a social preview image aligned with the minimalist repository identity.

## Release integrity

- Add signed tags once maintainer signing policy is finalized.
- Add detached signatures for `SHA256SUMS`.
- Evaluate keyless cosign signatures for release artifacts.
- Generate an SPDX SBOM for tagged releases.
- Add provenance once the release identity is stable.

## Platform support

- Keep Ubuntu 22.04 LTS and 24.04 LTS as primary targets.
- Maintain best-effort runtime awareness for WSL and containers.
- Avoid broad distro support until capability tests, package behavior, and rollback semantics are reliable.

## Not planned

- A monolithic installer rewrite.
- Hidden remote execution patterns.
- Storing secrets or Codex credentials.
- Kubernetes orchestration beyond environment detection until a concrete supported workflow exists.
