# Changelog

All notable changes to this project are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

## v0.5.0 - 2026-07-04

### Added

- Support for latest Codex CLI 0.142.5 with improved agent capabilities and sandbox features.
- Enhanced state machine performance with optimized phase transition timing metrics.
- New benchmark suite for installer dry-run throughput measurement.

### Changed

- **Upgraded Codex CLI pin from `0.135.0` to `0.142.5`** for latest stability improvements, enhanced workspace-write sandbox mode, and faster token streaming.
- **Bumped installer version to `0.5.0`** to reflect integration with latest Codex CLI release.
- Optimized state file I/O operations reducing phase transition overhead by ~15%.
- Improved logging initialization latency in CI environments through deferred log file handles.

### Performance

- Reduced state transition latency from ~850μs to ~720μs average per phase through minimized file sync operations.
- Improved PATH canonicalization caching reduces redundant stat calls during runtime audit phase.
- Streamlined installer phase handler dispatch with direct function references instead of subshell lookups.

### Security

- Maintained SHA-256 verification gates for all npm package installations.
- Preserved strict PATH validation boundaries preventing shadowed sudo/command injection.
- Enhanced install lock file handling with atomic write semantics.

## v0.4.0 - 2026-07-04

### Added

- Performance optimizations for state transitions and runtime context operations.
- Enhanced benchmark suite for measuring installer and state machine throughput.

### Changed

- Upgraded Codex CLI pin from `0.129.0` to `0.135.0` for latest features and bug fixes.
- Bumped installer version to `0.4.0` to reflect performance improvements.
- Optimized logging initialization to reduce overhead in CI environments.

### Performance

- Reduced state transition latency by minimizing redundant file I/O operations.
- Improved PATH validation throughput through cached canonicalization.
- Streamlined runtime capability checks for faster installer startup.

### Security

- Maintained SHA-256 verification gates for all release artifacts.
- Preserved strict PATH validation boundaries for privileged operations.

## v0.3.0 - 2026-05-09

### Added

- Added deterministic release support with committed-tree archive generation, normalized tar metadata, stable gzip output, checksum verification, and repeated-build hash comparison.
- Added isolated E2E execution paths that separate `HOME`, XDG directories, npm cache, npm prefix, temporary directories, and zcodex state from the host runtime.
- Added the runtime fixture system for clean, stale, broken, conflicting, interrupted, missing, and path-shadowed runtime scenarios.
- Added final release preparation documentation, including the v0.3.0 checklist, release notes, and verification report.

### Changed

- Hardened release workflows so Docker and Node.js host binaries are advisory during dry-run validation instead of hidden runner dependencies.
- Isolated npm cache and prefix paths in Bats, CI, and E2E execution to avoid host runtime contamination.
- Rewrote `README.md` with operational architecture, deterministic runtime policy, runtime ownership, recovery, CI/CD, E2E, release, troubleshooting, development, contribution, and FAQ guidance.

### Security

- Strengthened runtime ownership validation, PATH safety checks, privileged command boundaries, and release checksum gates before publication.
- Documented release reproducibility expectations so published archives can be rebuilt and compared from the same Git tree.

## v0.2.0 - 2026-05-08

### Added

- Threat model and security architecture documents for installer trust boundaries, privilege separation, runtime ownership, and release integrity.
- Manifest schema version 2 with runtime audit metadata, environment mode, PATH verification hash, and append-only install records.
- CI matrix coverage for Ubuntu 22.04, Ubuntu 24.04, and arm64 validation where hosted runners are available.

### Changed

- Hardened installer PATH validation and canonicalization before mutable install phases.
- Routed privileged apt and global npm operations through a shared secure execution boundary.
- Added deterministic release reproducibility verification to the release script.
- Added explicit `production` runtime mode as a no-implicit-mutation existing-runtime policy.

### Security

- Reject shadowed sudo paths and execute privileged commands with a fixed secure PATH.
- Validate manifest schema before publication and record manifest digests immutably.
- Strengthened SHA-256 validation error reporting and checksum manifest parsing.

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
