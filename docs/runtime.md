# Runtime Libraries

## `logging.sh`

Provides timestamped, CI-safe logging with stderr separation and optional terminal colors.

## `retry.sh`

Runs commands as arrays and retries them with exponential backoff. It does not evaluate shell strings.

## `platform.sh`

Validates Ubuntu releases and supported CPU architectures.

## `security.sh`

Centralizes temporary directory creation, cleanup, lock handling, checksum verification, and HTTPS-only downloads.

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
