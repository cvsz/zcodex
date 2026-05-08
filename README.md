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
- `platform.sh` for Ubuntu and architecture validation.
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

The installer performs these steps:

1. Validate Ubuntu release, CPU architecture, WSL status, and container runtime context.
2. Acquire an installation lock, secure temporary workspace, and rollback backup directory.
3. Update APT metadata and install base packages.
4. Install Node.js/npm and the Codex CLI.
5. Optionally install Docker and configure group membership.
6. Write a minimal Codex config and shell integration.

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

Doctor mode validates platform support, `PATH` safety, shell support, sudo/package-operation readiness, required tools (`bash`, `curl`, `git`, `node`, `npm`, `codex`), optional Docker availability, network access, and installed tool versions. Repair mode creates or permission-fixes the Codex config and reapplies idempotent shell integration without installing packages. If the installer cannot validate the host, confirm that you are running a supported Ubuntu release and architecture. If Docker group changes do not take effect immediately, log out and log back in. If `codex` is unavailable after installation, verify that npm global binaries are on your `PATH`.

## Rollback strategy

Before rewriting an existing Codex config or appending to an existing shell profile, the installer copies the original file into `${HOME}/.zcodex/backups/<timestamp>/` while preserving the source path under that backup root. Restore a file by copying the saved version back to its original location, then rerun `bash scripts/doctor.sh` to validate the runtime.

More details are available in `docs/troubleshooting.md`.
