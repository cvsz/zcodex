# zcodex Architecture

`zcodex` is an Ubuntu-first Codex CLI bootstrapper. The repository is intentionally split into an orchestration script and small runtime libraries so operational behavior can be tested without patching a monolithic installer.

## Layout

- `scripts/install-codex-ubuntu.sh` is the installation orchestration entry point.
- `codex.sh` is the release-style meta-orchestrator for basic, full, ultimate, doctor-only, and release validation flows.
- `scripts/lib/*.sh` contains reusable runtime functions, including the capability registry, manifest, pin, and state helpers.
- `tests/` contains Bats and shellcheck entry points.
- `.github/workflows/` contains CI validation for linting, installer behavior, and security scanning.
- `docs/` records architecture, runtime, troubleshooting, and security expectations.

## Runtime boundaries

`scripts/install-codex-ubuntu.sh` stays a thin entry point that establishes repository paths, loads `runtime.sh`, installs the cleanup trap, and delegates to `installer_run`. `codex.sh` stays outside the installer runtime and composes the existing installer, validator, and doctor scripts without duplicating install logic. The installer runtime library owns flag parsing, phase sequencing, dry-run behavior, optional component gates, and completion reporting. Platform-specific decisions are expressed as runtime capabilities rather than distro-specific installer branches. Domain libraries own implementation details for logging, retries, package installation, security primitives, Node.js, Docker, Codex, and shell integration.

## Design goals

- Avoid patch blobs and direct monolith edits.
- Keep shell functions composable and shellcheck-compatible.
- Preserve deterministic install behavior through explicit package lists, reviewed runtime pins, and a small capability registry.
- Centralize security-sensitive operations in `scripts/lib/security.sh`.
- Prefer explicit phase state and machine-readable manifests over implicit install assumptions.


## Deterministic install records

Installer runs write phase state below `${HOME}/.local/share/zcodex/state` and a JSON manifest at `${HOME}/.local/share/zcodex/manifest.json`. The state machine is linear (`VALIDATE`, `DOWNLOAD`, `VERIFY`, `INSTALL`, `CONFIGURE`, `VERIFY_RUNTIME`, `COMPLETE`, `FAILED`) so interrupted installs can be diagnosed and replayed without adding a second recovery framework. See `docs/manifest-state.md` for the schema and recovery strategy.

## Capability-driven platform abstraction

`platform.sh` now separates host identity from install decisions. It still reports OS release, architecture, WSL status, and container context for supportability, but install phases depend on four capabilities: `supports_apt`, `supports_systemd`, `supports_docker`, and `supports_rootless`. Ubuntu 22.04 and 24.04 remain the primary supported targets. Other hosts are not given distro-specific branches; if required capabilities are present, zcodex emits an unsupported best-effort warning and runs the same deterministic managed package path. See `docs/capabilities.md` for the capability model, examples, migration plan, and maintainability analysis.
