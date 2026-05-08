# Security Policy

`zcodex` is an installer and runtime bootstrapper, so security reports are taken seriously even when the affected code is shell-only.

## Supported versions

Security fixes target the latest release and the `main` branch. Older versions may receive fixes when the impact is high and the patch is low risk.

| Version | Supported |
| --- | --- |
| `main` | Yes |
| latest tagged release | Yes |
| older releases | Best effort |

## Reporting a vulnerability

Please report suspected vulnerabilities privately through GitHub Security Advisories for `cvsz/zcodex` when available. If GitHub private reporting is unavailable, contact the maintainer through the repository owner's public GitHub profile and avoid including exploit details in public issues.

Include:

- Affected version, commit, or tag.
- Host OS and architecture.
- Reproduction steps or proof of concept.
- Impact assessment.
- Whether the issue affects default installs, optional Docker setup, release artifacts, or local configuration.

## Response expectations

The maintainer will aim to:

1. Acknowledge valid reports within 7 days.
2. Confirm impact and affected versions.
3. Prepare a minimal fix and regression test when practical.
4. Publish a patched release and changelog entry for confirmed vulnerabilities.
5. Credit reporters unless they request otherwise.

## Security design scope

Security-sensitive project areas include:

- Download and checksum verification helpers.
- Installer temporary directories and cleanup.
- File permissions for manifests, state, config, and backups.
- Release artifact generation and checksum publication.
- Shell profile modification and rollback behavior.
- Optional Docker installation paths.

## Out of scope

The project does not provide a sandbox for arbitrary model-generated commands, does not store API keys, and does not replace host hardening. Users remain responsible for reviewing commands before running installer scripts on production systems.

## Hardening architecture references

- See [THREAT_MODEL.md](THREAT_MODEL.md) for assets, trust boundaries, and attack-surface mitigations.
- See [SECURITY_ARCHITECTURE.md](SECURITY_ARCHITECTURE.md) for PATH, privilege, runtime ownership, manifest, and release security architecture.
