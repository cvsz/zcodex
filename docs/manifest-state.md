# Deterministic install manifest and state tracking

This installer uses a small file-based state machine instead of a framework.  The
state directory is `~/.local/share/zcodex/state`, and the audit manifest is
`~/.local/share/zcodex/manifest.json`.

## Architecture proposal

The implementation has four shell modules:

- `scripts/lib/state.sh` owns the install state machine, phase history, status,
  install id, and resumable phase markers.
- `scripts/lib/manifest.sh` writes a deterministic JSON snapshot after each
  phase and at terminal states.
- `scripts/lib/installer.sh` orchestrates phases and performs interrupted-run
  recovery before mutable operations.
- `scripts/doctor.sh --repair` performs state-aware local repairs without
  re-running package installation implicitly.

The state machine phases are intentionally linear:

```text
VALIDATE -> DOWNLOAD -> VERIFY -> INSTALL -> CONFIGURE -> VERIFY_RUNTIME -> COMPLETE
                                                              \-> FAILED
```

`INSTALL` and `CONFIGURE` are marked complete after success.  If a process is
interrupted, the next run reads `current_phase`, `status`, `history.log`, and
`completed.d/*`, reruns validation, lock/workspace setup, and verification, then
skips completed mutable phases when safe.

## Manifest schema

The canonical manifest path is:

```text
~/.local/share/zcodex/manifest.json
```

Top-level fields required for auditing are:

```json
{
  "schema_version": 1,
  "installer_version": "0.2.0",
  "node_version": "v22.x.y",
  "docker_version": "Docker version ...",
  "codex_version": "codex ...",
  "install_timestamp": "2026-05-08T00:00:00Z",
  "platform_info": {
    "os_release": "/etc/os-release",
    "os": "Ubuntu ...",
    "id": "ubuntu",
    "version_id": "24.04",
    "arch": "x86_64",
    "normalized_arch": "amd64",
    "container_runtime": "none"
  },
  "architecture": "amd64",
  "install_state": {
    "phase": "VERIFY_RUNTIME",
    "status": "running",
    "install_id": "20260508T000000Z-1234",
    "state_dir": "/home/user/.local/share/zcodex/state"
  },
  "verification_hashes": {
    "manifest_inputs": "sha256...",
    "node": "sha256...",
    "npm": "sha256...",
    "docker": "sha256...",
    "codex": "sha256..."
  }
}
```

The file also retains compatibility sections (`installer`, `platform`, `state`,
`components`, and `packages`) so older tooling can continue to inspect component
status while newer tooling uses the required top-level audit fields.

## Shell code examples

Write phase state and a manifest snapshot:

```bash
state_mark INSTALL "install core runtime" running
installer_install_all
state_complete_phase INSTALL
manifest_write running
```

Detect and resume an interrupted installation:

```bash
INSTALLER_PREVIOUS_PHASE="$(state_current_phase 2>/dev/null || true)"
if [[ -n "${INSTALLER_PREVIOUS_PHASE}" && "${INSTALLER_PREVIOUS_PHASE}" != "COMPLETE" ]]; then
  log_warn "Interrupted install detected: $(state_recovery_summary)"
fi
```

Repair from state without silently mutating packages:

```bash
case "$(state_current_phase 2>/dev/null || true)" in
  CONFIGURE|VERIFY_RUNTIME|FAILED)
    repair_codex_config
    repair_shell_profile
    manifest_write repair
    ;;
  INSTALL)
    log_warn "Rerun the installer to complete package work."
    manifest_write repair
    ;;
esac
```

## Migration strategy

1. Existing installs without state are treated as unmanaged-but-auditable.
   `scripts/doctor.sh --repair --offline` initializes state at
   `VERIFY_RUNTIME` and writes a manifest from the current runtime.
2. Existing installs with an older manifest are overwritten atomically using a
   `.tmp` file and `mv`, preserving compatibility sections for current readers.
3. Interrupted installs keep their old `install_id`; completed installs reset
   progress markers before a fresh upgrade so new pins are applied
   deterministically.
4. Operators can pin versions through the existing `ZCODEX_*_VERSION`
   environment variables; those pins are recorded in component desired versions
   and the `verification_hashes.manifest_inputs` digest.

## Failure recovery design

- Every phase transition is appended to `state/history.log` with UTC timestamp,
  phase, status, install id, and a short message.
- `current_phase` and `status` are single-purpose files for simple shell
  inspection.
- `completed.d/INSTALL` and `completed.d/CONFIGURE` allow the next installer run
  to avoid redoing successfully completed mutable phases.
- Validation, lock/workspace setup, and pin verification always rerun on resume
  because they are cheap and protect the resumed run.
- Failed runs are terminally marked as `FAILED` and also emit a manifest with
  `install_state.status=failed` for auditing.

## Rollback logic

Rollback stays deliberately narrow:

- Before configuration changes, files are copied into a timestamped backup under
  `~/.zcodex/backups/<timestamp>/`.
- On installer failure, `backup_restore_all` restores files touched in the
  current backup directory when `ZCODEX_ROLLBACK_ON_FAILURE=true` (default).
- Package manager operations are not automatically rolled back; they are
  idempotent and safer to repair or complete with a subsequent installer run
  than to downgrade blindly.
- Set `ZCODEX_ROLLBACK_ON_FAILURE=false` when debugging a failed configuration
  step and you want to inspect the partially written files.

## Schema v2, migration, integrity, and reconciliation

Manifest schema v2 is the only writable schema for current releases. Legacy v1
manifests are treated as recovery input and must be migrated with
`manifest_migrate_file SOURCE [TARGET]` before they are accepted by strict
validation. The v1 to v2 migration preserves phase/status, installer metadata,
components, packages, platform facts, and verification hashes where present, and
records the migration in a `migrations` array.

Writers use deterministic JSON serialization (`sort_keys`, two-space
indentation, UTF-8, trailing newline) and then seal the document with
`integrity.canonical_sha256`. The digest is calculated over the same canonical
JSON with `integrity.canonical_sha256` blanked, which gives operators a stable
integrity check without a self-referential hash loop. Validation rejects
corrupted JSON, unsupported schema versions, invalid phases/statuses, missing
component names, and integrity mismatches.

State reconciliation is explicit and conservative:

1. Validate persisted `current_phase` against the known phase set.
2. Validate persisted `status` against the known status set.
3. Remove invalid completed-phase marker files under `completed.d/`.
4. Normalize stale `COMPLETE`/status combinations.
5. Mark the install `FAILED` if persisted phase or status is invalid.

Interrupted installs remain resumable because completed phase markers are
advisory and individually validated before the installer skips work.
