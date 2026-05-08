# zcodex Architecture

`zcodex` is an Ubuntu-focused Codex CLI bootstrapper. The repository is intentionally split into an orchestration script and small runtime libraries so operational behavior can be tested without patching a monolithic installer.

## Layout

- `scripts/install-codex-ubuntu.sh` is the orchestration entry point.
- `scripts/lib/*.sh` contains reusable runtime functions.
- `tests/` contains Bats and shellcheck entry points.
- `.github/workflows/` contains CI validation for linting, installer behavior, and security scanning.
- `docs/` records architecture, runtime, troubleshooting, and security expectations.

## Runtime boundaries

The installer owns sequencing only: parse flags, validate the platform, acquire locks, call libraries, and report completion. Libraries own implementation details for logging, retries, package installation, security primitives, Node.js, Docker, Codex, and shell integration.

## Design goals

- Avoid patch blobs and direct monolith edits.
- Keep shell functions composable and shellcheck-compatible.
- Preserve deterministic install behavior through explicit package lists.
- Centralize security-sensitive operations in `scripts/lib/security.sh`.
