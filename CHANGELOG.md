# Changelog

All notable changes to this project are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Added

- Root MIT license file and license verification guidance.
- Contributor guide, security policy, roadmap, release checklist, and release notes template.
- Repository audit and GitHub presentation strategy documentation.
- Bug report and support issue templates.

### Changed

- Expanded README with CI badges, architecture diagrams, installation paths, troubleshooting flow, release documentation, and open-source readiness links.

## v0.1.0 - 2026-05-08

Initial public release of zcodex.

### Added

- Modular Ubuntu bootstrap installer for Codex CLI environments.
- Codex CLI installation and runtime validation flow.
- Optional Docker installation path.
- Security-focused HTTPS download helpers with SHA-256 verification support.
- Rollback backups before managed user file changes.
- Dry-run and CI-safe operation modes.
- Shellcheck, shfmt, and Bats validation coverage.
- Manifest, state-machine, doctor, and environment validation tooling.

### Supported

- Ubuntu 22.04 LTS and Ubuntu 24.04 LTS.
- amd64/x86_64 and arm64/aarch64 architectures.

### Security

- HTTPS-only download policy for release and installer fetches.
- SHA-256 checksum generation for release artifacts.
- Lockfile protection for installer runs.
- Secure temporary directories with cleanup traps.
