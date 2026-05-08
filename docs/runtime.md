# Runtime Libraries

## `runtime.sh`

Loads the full modular runtime stack for entry points that need installer, security, and repair helpers without duplicating source order.

## `installer.sh`

Owns installer-specific CLI parsing, phase sequencing, dry-run behavior, optional component gates, and trap cleanup so `install-codex-ubuntu.sh` remains a thin entry point.

## `logging.sh`

Provides timestamped, CI-safe logging with stderr separation and optional terminal colors.

## `retry.sh`

Runs commands as arrays and retries them with exponential backoff. It does not evaluate shell strings.

## `platform.sh`

Validates Ubuntu releases and supported CPU architectures.

## `security.sh`

Centralizes temporary directory creation, cleanup, lock handling, SHA-256 checksum verification, checksum manifest lookup, and HTTPS-only downloads.

## `pins.sh`

Defines reviewed runtime version pins for Node.js, Docker apt packages, the Docker Compose plugin, the Codex CLI, and future managed runtime dependencies.

## `state.sh`

Writes explicit phase state and append-only phase history below `${HOME}/.local/share/zcodex/state` for interrupted install diagnosis and deterministic replay.

## `manifest.sh`

Writes `${HOME}/.local/share/zcodex/manifest.json` with installer metadata, platform metadata, current phase, component versions, package versions, and best-effort command hashes.

## `backup.sh`

Creates a per-run backup root and preserves existing user-managed files before the installer rewrites Codex config or appends shell profile integration.

## `packages.sh`

Wraps `apt-get update` and deterministic non-interactive package installation.

## `nodejs.sh`

Installs Node.js/npm and npm global packages.

## `docker.sh`

Installs Docker from Ubuntu repositories and optionally configures user group membership.

## `codex.sh`

Installs the Codex CLI and writes the minimal Codex config schema.

## `shell.sh`

Adds idempotent shell profile integration outside CI mode.
