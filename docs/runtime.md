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

Provides host facts, validates supported CPU architectures, and owns the runtime capability registry (`supports_apt`, `supports_systemd`, `supports_docker`, and `supports_rootless`). Ubuntu 22.04/24.04 remains the primary target, while non-Ubuntu hosts are accepted only when required capabilities are present and are logged as unsupported best-effort environments.

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

Wraps `apt-get update` and deterministic non-interactive package installation after checking `supports_apt`.

## `nodejs.sh`

Installs Node.js/npm through the managed package capability and installs npm global packages.

## `docker.sh`

Installs Docker through the managed APT package path, gates service enablement on `supports_systemd`, and optionally configures user group membership.

## `codex.sh`

Installs the Codex CLI and writes the minimal Codex config schema.

## `shell.sh`

Adds idempotent shell profile integration outside CI mode.
