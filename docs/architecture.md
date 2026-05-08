# zcodex Architecture

`zcodex` is an Ubuntu-focused Codex CLI bootstrapper. The repository is intentionally split into an orchestration script and small runtime libraries so operational behavior can be tested without patching a monolithic installer.

## Layout

- `scripts/install-codex-ubuntu.sh` is the orchestration entry point.
- `scripts/lib/*.sh` contains reusable runtime functions.
- `tests/` contains Bats and shellcheck entry points.
- `.github/workflows/` contains CI validation for linting, installer behavior, and security scanning.
- `docs/` records architecture, runtime, troubleshooting, and security expectations.

## Runtime boundaries

`scripts/install-codex-ubuntu.sh` stays a thin entry point that establishes repository paths, loads `runtime.sh`, installs the cleanup trap, and delegates to `installer_run`. The installer runtime library owns flag parsing, phase sequencing, dry-run behavior, optional component gates, and completion reporting. Domain libraries own implementation details for logging, retries, package installation, security primitives, Node.js, Docker, Codex, and shell integration.

## Design goals

- Avoid patch blobs and direct monolith edits.
- Keep shell functions composable and shellcheck-compatible.
- Preserve deterministic install behavior through explicit package lists.
- Centralize security-sensitive operations in `scripts/lib/security.sh`.
