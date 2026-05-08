# zcodex

`zcodex` is a clean, modular Ubuntu bootstrapper for installing and validating the Codex CLI runtime. The repository is regenerated around small shell libraries, CI validation, and security-focused installation primitives instead of monolithic patch maintenance.

## Supported OS

- Ubuntu 22.04 LTS
- Ubuntu 24.04 LTS
- Architectures: `x86_64`/`amd64`, `aarch64`/`arm64`
- Runtime awareness: native Ubuntu, WSL, and common container runtimes are detected before installation

## Repository architecture

```text
zcodex/
├── .codex/                  # Codex config and agent instructions
├── scripts/                 # Installer entry points
│   └── lib/                 # Shared runtime libraries
├── tests/                   # Bats and shellcheck checks
├── .github/workflows/       # CI, installer, and security workflows
└── docs/                    # Architecture, runtime, security, troubleshooting
```

The main installer is an orchestration layer. Reusable behavior lives in `scripts/lib`:

- `logging.sh` for structured CI-safe logs.
- `retry.sh` for array-based exponential backoff.
- `pins.sh`, `state.sh`, and `manifest.sh` for deterministic version pins, explicit install phases, and machine-readable install records.
- `platform.sh` for host facts, architecture validation, and the runtime capability registry (`supports_apt`, `supports_systemd`, `supports_docker`, `supports_rootless`).
- `runtime.sh` for consistent modular library loading.
- `installer.sh` for CLI flag parsing, install-phase sequencing, and trap cleanup.
- `security.sh` for tempfiles, locks, HTTPS downloads, direct checksums, and checksum manifests.
- `backup.sh` for rollback snapshots before Codex config or shell profile changes.
- `packages.sh`, `nodejs.sh`, `docker.sh`, `codex.sh`, and `shell.sh` for install-specific domains.

## Security model

- No `curl | bash` or `curl | sh` execution patterns.
- HTTPS-only download helper with strict curl flags.
- Optional SHA-256 verification for downloaded artifacts, including `SHA256SUMS`-style manifest entries.
- `mktemp -d` workspaces with trap-based cleanup.
- Timestamped rollback backups under `${HOME}/.zcodex/backups/` before overwriting managed user files.
- `flock` protection against concurrent installer runs.
- Manifest and phase state files under `${HOME}/.local/share/zcodex/` with private directory and file permissions.
- Minimal Codex config generation without storing secrets.

## Installation flow

```bash
bash scripts/install-codex-ubuntu.sh
```

Common options:

```bash
CI=true bash scripts/install-codex-ubuntu.sh --ci --skip-docker
bash scripts/install-codex-ubuntu.sh --skip-optional
bash scripts/install-codex-ubuntu.sh --dry-run --skip-docker --skip-optional
```

For release-style operations, use the unified orchestrator:

```bash
./codex.sh basic --dry-run --skip-docker
./codex.sh orchestrator --offline --repair
./codex.sh release --skip-optional
```

The orchestrator writes a combined operational log to `codex_release.log` by default, or to `ZCODEX_RELEASE_LOG` when that environment variable is set.

The installer performs these explicit state-machine phases:

1. `VALIDATE`: validate runtime capabilities, CPU architecture, WSL status, container runtime context, Ubuntu-first support status, and version pins.
2. `DOWNLOAD`: acquire an installation lock, secure temporary workspace, and rollback backup directory.
3. `VERIFY`: detect interrupted prior state and revalidate pins.
4. `INSTALL`: update APT metadata, install base packages, pinned Node.js, pinned Codex CLI, and optional Docker.
5. `CONFIGURE`: write a minimal Codex config and shell integration.
6. `VERIFY_RUNTIME`: validate runtime commands and write a running manifest snapshot.
7. `COMPLETE` or `FAILED`: write final state and `${HOME}/.local/share/zcodex/manifest.json`.

## Codex config

The repository config intentionally stays minimal and valid:

```toml
model = "gpt-5-codex"

approval-policy = "on-request"
sandbox-mode = "workspace-write"
```

## Development

```bash
make lint
make fmt-check
make test
make doctor
```

Equivalent direct commands:

```bash
bash -n codex.sh scripts/*.sh scripts/lib/*.sh tests/*.sh
{ printf '%s\0' codex.sh; find scripts tests -type f -name '*.sh' -print0; } | xargs -0 shellcheck
shfmt -d codex.sh scripts tests
bats tests
```

## CI

CI runs shell syntax checks, shellcheck, a dedicated shfmt formatting workflow, Bats tests, installer dry-run validation, Gitleaks, and Trivy filesystem scanning.

## Releases

zcodex uses semantic versioning and publishes release artifacts from Git tags. The version source of truth is `VERSION`, tags use the `vX.Y.Z` format, and release notes are extracted from `CHANGELOG.md`.

Create a release by tagging the committed tree:

```bash
git tag v0.1.0
git push origin v0.1.0
```

The release workflow runs ShellCheck, shfmt, and Bats; builds `zcodex-vX.Y.Z.tar.gz` with deterministic `git archive` plus `gzip -n`; generates `SHA256SUMS`; verifies checksums; and publishes a GitHub Release. Local dry runs use:

```bash
make release
make release-checksum
```

Future release hardening is planned for GPG signatures, cosign blob signatures, SBOM generation, signed tags, and provenance. See `docs/release.md` for the complete release architecture.

## Troubleshooting

Start with:

```bash
bash scripts/doctor.sh
```

For airgapped or tightly proxied environments, skip outbound connectivity checks while still validating local runtime state:

```bash
bash scripts/doctor.sh --offline
bash scripts/doctor.sh --repair
```

Doctor mode validates platform support, `PATH` safety, shell support, sudo/package-operation readiness, required tools (`bash`, `curl`, `git`, `node`, `npm`, `codex`), optional Docker availability, network access, and installed tool versions. Repair mode creates or permission-fixes the Codex config and reapplies idempotent shell integration without installing packages. If the installer cannot validate the host, confirm that the architecture is supported and the APT capability is available; Ubuntu 22.04 and 24.04 remain the primary supported targets. If Docker group changes do not take effect immediately, log out and log back in. If `codex` is unavailable after installation, verify that npm global binaries are on your `PATH`.

## Rollback strategy

Before rewriting an existing Codex config or appending to an existing shell profile, the installer copies the original file into `${HOME}/.zcodex/backups/<timestamp>/` while preserving the source path under that backup root. Restore a file by copying the saved version back to its original location, then rerun `bash scripts/doctor.sh` to validate the runtime.

Manifest and state design details are available in `docs/manifest-state.md`. More troubleshooting details are available in `docs/troubleshooting.md`.
