# Security Model

## Download policy

The runtime rejects non-HTTPS downloads and uses `curl` with strict TLS options when downloads are required. The repository does not use `curl | bash` or `curl | sh` patterns.

## Temporary files

Temporary workspaces are created with `mktemp -d`, restricted to mode `700`, and removed by the installer's exit trap.

## Locking

Installer execution is guarded by `flock` to prevent concurrent mutation of packages and Codex configuration.

## Rollback backups

Existing user files are backed up before zcodex rewrites Codex config or appends shell profile integration. Backups are stored below `${HOME}/.zcodex/backups/<timestamp>/` with the original absolute path recreated under the backup root.

## Checksums

`security_verify_sha256` validates downloaded files when callers provide an expected SHA-256 digest.

## Secrets

The installer does not write API keys. Users should configure credentials through the official Codex CLI authentication flow or their environment.
