# zcodex

[![ci](https://github.com/cvsz/zcodex/actions/workflows/ci.yml/badge.svg)](https://github.com/cvsz/zcodex/actions/workflows/ci.yml)
[![e2e](https://github.com/cvsz/zcodex/actions/workflows/e2e.yml/badge.svg)](https://github.com/cvsz/zcodex/actions/workflows/e2e.yml)
[![release-validate](https://github.com/cvsz/zcodex/actions/workflows/release-validate.yml/badge.svg)](https://github.com/cvsz/zcodex/actions/workflows/release-validate.yml)
[![release](https://github.com/cvsz/zcodex/actions/workflows/release.yml/badge.svg)](https://github.com/cvsz/zcodex/actions/workflows/release.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

`zcodex` is a Bash-based Ubuntu bootstrapper for Codex CLI runtimes. It installs and validates a small, auditable runtime using deterministic phase ordering, explicit state files, runtime ownership checks, reproducible release artifacts, and CI-visible validation paths.

## Project overview

The repository is maintained as infrastructure code, not as a remote installer blob. Entry points call small Bash libraries under `scripts/lib/`, write runtime state under XDG-style directories, and expose repeatable checks through `make` targets and GitHub Actions.

Primary goals:

- Bootstrap Codex CLI on supported Ubuntu hosts.
- Keep installer behavior reviewable and shellcheck-compatible.
- Detect unsafe `PATH`, runtime ownership, and package-manager conflicts before mutation.
- Support dry-run, repair, diagnostics, release, and E2E workflows.
- Produce release archives with reproducible SHA-256 hashes for a fixed Git tree.

## Architecture overview

```text
operator / CI
  ├─ codex.sh                         # workflow orchestrator
  ├─ scripts/install-codex-ubuntu.sh   # installer entry point
  ├─ scripts/doctor.sh                 # runtime validation and repair
  ├─ scripts/e2e-runner.sh             # isolated Ubuntu scenario runner
  └─ scripts/release.sh                # deterministic release builder

scripts/lib/
  ├─ runtime, installer, state, manifest
  ├─ platform, environment, dependencies
  ├─ security, exec, retry, backup
  └─ packages, nodejs, docker, codex, shell
```

The installer advances through `VALIDATE`, `DOWNLOAD`, `VERIFY`, `INSTALL`, `CONFIGURE`, `VERIFY_RUNTIME`, and `COMPLETE`. Failures mark `FAILED` and preserve enough state for doctor and diagnostics workflows to explain the recovery path.

## Deterministic runtime philosophy

`zcodex` minimizes ambient host assumptions. Runtime decisions are made from observed capabilities, pinned expectations, explicit flags, and committed fixtures rather than from a developer workstation's current shell state.

Determinism is enforced by:

- Sorted, normalized release archives with stable gzip headers.
- CI and E2E plans that isolate npm cache, prefix, home, state, and temporary paths.
- Runtime fixture tests for clean, stale, broken, conflicting, interrupted, and shadowed environments.
- Linear phase state and manifest records for installs.
- Secure command lookup rules that reject unsafe `PATH` entries and shadowed privileged tools.

## Runtime ownership model

The installer audits visible `node`, `npm`, and `codex` binaries before modifying the system. It classifies runtimes as apt distro, NodeSource, nvm, asdf, system-unowned, unknown, or absent, then applies a runtime-mode policy.

| Mode | Use case | Mutation policy |
| --- | --- | --- |
| `clean-system` | Fresh supported Ubuntu host | May install managed apt packages when no unsafe conflict exists. |
| `existing-runtime` | Workstation with activated Node.js/npm | Does not mutate Node.js/npm; requires compatible active tools. |
| `ci` | Prebuilt CI image | Does not mutate Node.js/npm; selected by `--ci`. |
| `developer` | Explicit local development override | Allows user-runtime mutation only when the opt-in environment flag is set. |
| `production` | Locked runtime host | No implicit runtime mutation; conflicts fail early. |

## Supported platforms

Primary support targets:

- Ubuntu 22.04 LTS and Ubuntu 24.04 LTS.
- `amd64`/`x86_64` and `arm64`/`aarch64`.
- Native Ubuntu hosts, common containers, and WSL-aware execution.

Other Linux environments are best-effort only. Capability checks determine whether apt, systemd, Docker, sudo, rootless behavior, and required shell tooling are available. Unsupported hosts should use dry-run and doctor mode before any installation attempt.

## Install instructions

Clone the repository and run the installer:

```bash
git clone https://github.com/cvsz/zcodex.git
cd zcodex
bash scripts/install-codex-ubuntu.sh
```

Recommended review path:

```bash
CI=true bash scripts/install-codex-ubuntu.sh --dry-run --skip-docker --skip-optional
bash scripts/doctor.sh --offline
```

Or use the orchestrator:

```bash
./codex.sh basic --dry-run --skip-docker
./codex.sh full --skip-optional
./codex.sh ultimate --skip-docker
./codex.sh orchestrator --offline --repair
./codex.sh release --skip-optional
```

## Installer options

Common flags:

| Flag | Purpose |
| --- | --- |
| `--dry-run` | Print the plan without package, npm, Docker, or shell-profile mutation. |
| `--skip-docker` | Do not install or validate Docker as part of the install path. |
| `--skip-optional` | Skip optional components and keep the runtime minimal. |
| `--ci` | Select CI-safe runtime behavior and noninteractive defaults. |
| `--runtime-mode MODE` | Select `clean-system`, `existing-runtime`, `ci`, `developer`, or `production`. |

Use `bash scripts/install-codex-ubuntu.sh --help` for the active flag list.

## Repair and recovery workflows

Run doctor mode first when a host is already modified or partially configured:

```bash
bash scripts/doctor.sh
bash scripts/doctor.sh --offline
bash scripts/doctor.sh --repair
```

Repair mode can recreate missing Codex configuration, restrict config permissions, and reapply idempotent shell integration without installing packages. For interrupted installs, inspect `${HOME}/.local/share/zcodex/state`, the manifest, and backups under `${HOME}/.zcodex/backups/` before retrying.

Generate a deterministic diagnostics bundle when a failure needs review:

```bash
bash scripts/diagnostics.sh
```

## CI/CD overview

The CI system is intentionally close to local commands. `make validate` runs environment checks, ShellCheck, shfmt diff checks, workflow policy checks, Bats tests, and E2E dry-run plans.

GitHub Actions responsibilities:

| Workflow | Responsibility |
| --- | --- |
| `ci` | Linting, formatting, unit tests, workflow policy, dry-run E2E, security checks, and release reproducibility checks. |
| `e2e` | Containerized Ubuntu scenario validation for supported OS and architecture combinations. |
| `release-validate` | VERSION, tag, changelog, orchestrator, and deterministic artifact validation. |
| `release` | Tag-triggered release artifact build, checksum verification, and GitHub Release publication. |

## E2E validation overview

E2E validation is driven by `scripts/e2e-runner.sh` and `tests/e2e/scenarios.tsv`. Scenarios cover fresh install, repair, manifest reconciliation, interrupted state, strict mode, CI mode, and runtime conflicts.

Examples:

```bash
bash scripts/e2e-runner.sh --dry-run --ubuntu 24.04 --arch amd64
bash scripts/e2e-runner.sh --ubuntu 22.04 --arch arm64 --scenario fresh-install
```

Container runs isolate `HOME`, `TMPDIR`, npm cache, npm prefix, XDG paths, and zcodex state. Failure logs and copied state are written below `artifacts/e2e/`.

## Release verification

`VERSION` is the semantic-version source of truth and must match the release tag without the leading `v`. For this release, `VERSION` is `0.3.0` and the tag contract is `v0.3.0`.

Local release verification:

```bash
bash scripts/validate-release.sh v0.3.0
bash scripts/release.sh --skip-validate
bash scripts/verify-release-artifacts.sh dist
make release-reproducible
```

The release archive is generated from a committed Git tree, normalized with sorted tar entries, fixed ownership, fixed mtime, UTC locale, and `gzip -n`. `SHA256SUMS` must verify before publishing.

## Troubleshooting

Start with a dry run and doctor check:

```bash
CI=true bash scripts/install-codex-ubuntu.sh --dry-run --skip-docker --skip-optional
bash scripts/doctor.sh --offline
```

Common causes:

- Unsupported OS or architecture: use Ubuntu 22.04/24.04 on amd64 or arm64.
- Unsafe `PATH`: remove empty entries, current-directory lookup, and writable executable directories.
- Runtime conflict: select the correct `--runtime-mode` or normalize Node.js/npm ownership.
- Docker group not active: log out and back in after group membership changes.
- Codex unavailable: confirm npm global bin paths and rerun doctor mode.

## Development workflow

Install development dependencies on Ubuntu when needed:

```bash
make deps-dev
```

Run the standard local gates:

```bash
make lint
make fmt-check
make test
make e2e-dry-run
make validate
```

Format shell files with `make fmt`. Keep generated artifacts such as `dist/`, `artifacts/`, diagnostics bundles, local logs, npm caches, and temporary state out of commits.

## Contributing guide

Contributions should keep Bash code explicit, portable within the supported Ubuntu targets, and compatible with ShellCheck and shfmt. Prefer small library functions over large entry-point edits, and update tests or fixtures when behavior changes.

Before opening a pull request:

- Run `make validate` or document any environment limitation.
- Update `README.md`, `CHANGELOG.md`, and docs for user-visible behavior.
- Avoid introducing `curl | bash`, unchecked downloads, broad `sudo` calls, or mutable global state.
- Keep release artifacts generated from committed source, not from untracked build output.

Security issues should be reported through `SECURITY.md`, not public issues.

## FAQ

### Does zcodex install with `curl | bash`?

No. The supported path is cloning the repository, reviewing the scripts, and running local entry points.

### Can I run it without Docker?

Yes. Use `--skip-docker` for installation paths that should not install or validate Docker. Some E2E workflows require Docker unless run with `--dry-run`.

### What should I use on a workstation with nvm or asdf?

Activate the desired runtime and use `--runtime-mode existing-runtime`. The default clean-system path is designed for hosts where zcodex may manage apt packages.

### How are releases made reproducible?

Release scripts archive the committed tree with stable sorting, ownership, mtime, locale, and gzip metadata. The release workflow verifies checksums and rebuilds the archive to compare hashes.

### Where are runtime records stored?

State and manifests are stored below `${HOME}/.local/share/zcodex/` by default. Backups of managed user files are stored below `${HOME}/.zcodex/backups/`.

### Is this only for Ubuntu?

Production support targets Ubuntu 22.04 and 24.04 on amd64 and arm64. Other environments may pass capability checks, but they are best-effort and should be validated with dry-run and doctor mode first.
