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

`security_verify_sha256` validates downloaded files when callers provide an expected SHA-256 digest. `security_verify_manifest_entry` and `security_download_verified` support a `SHA256SUMS`-style manifest so CI and future artifact-download callers can require a named checksum entry before accepting downloaded content.

## Secrets

The installer does not write API keys. Users should configure credentials through the official Codex CLI authentication flow or their environment.

## PATH risk engine

PATH validation is risk-scored instead of binary allow/deny validation. Each canonical PATH entry is classified as `TRUSTED_SYSTEM`, `USER_LOCAL_SAFE`, `USER_LOCAL_RISKY`, or `UNKNOWN`, then scored from a base risk plus modifiers for user-local, unknown, writable/executable, and pre-system-path placement. Trusted system entries start at 0; non-system entries start at 20 so critical combinations can cross the strict-mode blocking threshold. Strict validation blocks only entries whose score reaches 85 or higher; all other non-zero scores are warnings with an explanation.

`security_analyze_path` emits one JSON object per PATH entry with this shape:

```json
{"path":"...","classification":"...","risk_score":0,"reason":"...","action":"allow"}
```

The installer continues to reject structurally unsafe PATH values such as empty segments, relative entries, and unreadable directories before applying risk decisions.
