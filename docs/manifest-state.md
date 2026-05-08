# Deterministic Manifests and Install State

## Executive summary

`zcodex` now records what it intended to install, what it observed after installation, and where the installer stopped. The implementation is intentionally small: version pins live in `scripts/lib/pins.sh`, phase state lives under `${HOME}/.local/share/zcodex/state`, and the machine-readable manifest is written to `${HOME}/.local/share/zcodex/manifest.json`.

The design favors deterministic repair over package-manager complexity. The installer always replays the same explicit phases, validates configured pins, updates the state file before mutating each area, and writes a final manifest on success or failure.

## Architecture review

The existing project already separates orchestration from domain libraries. The new state layer preserves that shape:

- `installer.sh` owns phase sequencing and decides when a phase starts.
- `pins.sh` owns immutable desired versions for managed dependencies.
- `state.sh` owns the current phase and append-only phase history.
- `manifest.sh` owns JSON emission and observed runtime metadata.
- Existing domain libraries (`nodejs.sh`, `docker.sh`, `codex.sh`) consume pins instead of inventing local version policy.

No plugin system or package database is introduced. The manifest is an operational record, not an independent package manager.

## Proposed design

### Version pinning

Default pins are shell variables with environment overrides for CI and controlled rollouts:

- `ZCODEX_INSTALLER_VERSION`
- `ZCODEX_NODEJS_VERSION`
- `ZCODEX_NODEJS_PACKAGE_VERSION`
- `ZCODEX_DOCKER_PACKAGE_VERSION`
- `ZCODEX_DOCKER_COMPOSE_PACKAGE_VERSION`
- `ZCODEX_CODEX_CLI_VERSION`

`ZCODEX_CODEX_CLI_VERSION` is exact because npm accepts `@openai/codex@<version>`. Node.js is validated against the configured semver or major-version pin after install. Ubuntu Docker package versions are optional exact apt pins because exact package versions vary by Ubuntu release and mirror; when unset, the manifest records the Ubuntu candidate that was actually installed.

### Manifest

The manifest is JSON, mode `600`, and replaced atomically through a temporary file plus `mv`. It contains installer metadata, platform metadata, current state, component versions, package versions, and hashes for command paths when readable.

### State tracking

The state tracker writes:

- `state/current_phase` with the latest phase.
- `state/history.log` with UTC timestamp, phase, install id, and message.
- `state/install_id` with the run identifier.

The installer records phases before each mutable section so interrupted runs can be diagnosed and re-run deterministically.

## File layout

```text
${HOME}/.local/share/zcodex/
├── manifest.json
└── state/
    ├── current_phase
    ├── history.log
    └── install_id
```

Repository additions:

```text
scripts/lib/pins.sh       # version pin definitions and validation
scripts/lib/state.sh      # phase tracking
scripts/lib/manifest.sh   # manifest JSON writer
docs/manifest-state.md    # design and operations guide
```

## Manifest schema

Schema version `1` is intentionally compact:

```json
{
  "schema_version": 1,
  "installer": {
    "name": "zcodex",
    "version": "0.2.0",
    "install_id": "20260508T120000Z-1234",
    "written_at": "2026-05-08T12:00:00Z"
  },
  "platform": {
    "os": "Ubuntu 24.04 LTS",
    "id": "ubuntu",
    "version_id": "24.04",
    "arch": "x86_64",
    "normalized_arch": "amd64",
    "container_runtime": "none"
  },
  "state": {
    "phase": "COMPLETE",
    "status": "complete"
  },
  "components": [
    {
      "name": "nodejs",
      "desired_version": "22",
      "installed_version": "v22.16.0",
      "status": "installed",
      "sha256": "..."
    }
  ],
  "packages": {
    "nodejs": "...",
    "npm": "...",
    "docker.io": "...",
    "docker-compose-plugin": "..."
  }
}
```

Unknown hashes and missing package versions are recorded as `null`, not omitted.

## State machine flow

```text
VALIDATE
  Validate platform and pins before mutation.
DOWNLOAD
  Acquire lock, create secure temp workspace, initialize backup root.
VERIFY
  Detect interrupted prior state and revalidate pins.
INSTALL
  Update apt metadata, install base packages, Node.js, Codex CLI, optional Docker.
CONFIGURE
  Write Codex config and shell integration with backups.
VERIFY_RUNTIME
  Validate runtime commands and write a running manifest snapshot.
COMPLETE
  Mark success and write the final complete manifest.
FAILED
  Mark failure and write the final failed manifest from the cleanup trap.
```

Resume and repair are intentionally replay based. A future `--repair` path should read `manifest.json`, compare desired and installed versions, then run the same small domain functions rather than executing hidden recovery logic.

## Shell implementation examples

Pin validation:

```bash
: "${ZCODEX_CODEX_CLI_VERSION:=0.129.0}"

pins_validate_semver_or_major() {
	local value="$1"
	[[ "${value}" =~ ^[0-9]+([.][0-9]+){0,2}([+-][A-Za-z0-9._-]+)?$ ]]
}
```

Phase tracking:

```bash
state_mark INSTALL "install core runtime"
packages_update
packages_install_base
nodejs_install_ubuntu
codex_install_cli
```

Atomic manifest write:

```bash
cat >"${ZCODEX_MANIFEST_FILE}.tmp" <<JSON
{
  "schema_version": 1,
  "state": { "phase": "${phase}", "status": "${status}" }
}
JSON
chmod 600 "${ZCODEX_MANIFEST_FILE}.tmp"
mv "${ZCODEX_MANIFEST_FILE}.tmp" "${ZCODEX_MANIFEST_FILE}"
```

## Migration steps

1. Existing installs have no manifest and no state directory. The next installer run creates both automatically.
2. Existing Codex config and shell profile backup behavior is unchanged.
3. Existing users can set stricter apt pins before running the installer:

   ```bash
   ZCODEX_NODEJS_PACKAGE_VERSION='22.16.0-1nodesource1' \
   ZCODEX_DOCKER_PACKAGE_VERSION='24.0.7-0ubuntu4.1' \
   bash scripts/install-codex-ubuntu.sh
   ```

4. CI can assert manifest validity with `python3 -m json.tool ~/.local/share/zcodex/manifest.json` or `jq` after a non-dry-run install.

## Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| Ubuntu package versions differ by release or mirror | Exact apt package pins are opt-in and recorded in the manifest; defaults still validate runtime versions. |
| Interrupted install leaves partial state | The next run logs the previous phase and replays deterministic phases. |
| Manifest writer depends on unavailable `jq` | JSON is emitted by Bash with explicit escaping and validated in tests with Python. |
| Command hashes can point at symlinks or wrappers | Hashes are best-effort verification metadata and are `null` when unavailable. Package versions remain authoritative for apt-managed tools. |
| Pin drift causes unexpected upgrades | Codex CLI installs an exact npm version; Node.js fails if the observed version does not satisfy the pin. |

## Security considerations

- State and manifest directories are created with mode `700`; files are written with mode `600`.
- Download security remains centralized in `security.sh` and still refuses non-HTTPS downloads.
- The manifest stores versions and hashes only; it does not store tokens, environment dumps, npm config, or shell history.
- Failure manifests are written from the cleanup trap to make incident review possible.
- Package pins are validated before installation to avoid command injection through package spec construction.

## Rollback and recovery logic

Rollback remains file based for managed user files: config and shell profile changes are backed up before rewrite. Recovery is deterministic replay:

1. Inspect `state/current_phase` and `state/history.log`.
2. Inspect `manifest.json` if it exists.
3. Restore backed-up config files when needed.
4. Re-run the installer with the same pins.
5. Confirm the final manifest reports `state.status=complete` and `state.phase=COMPLETE`.

Future upgrade support should add a small comparator that reads desired pins, compares them with manifest component versions, and calls existing install functions. It should not introduce a second installation path.

## Final recommendations

- Keep pins explicit and reviewed in `pins.sh`.
- Prefer exact pins for npm and optional exact apt package versions in production images.
- Treat the manifest as an audit and repair input, not as a mutable source of truth.
- Keep state transitions in `installer.sh` only so the install flow remains understandable.
- Extend `components[]` for future runtime dependencies instead of changing the top-level schema for every new tool.
