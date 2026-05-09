```md
# AGENTS.md — zcodex Codex-Max Agent Instructions
# Repository: https://github.com/cvsz/zcodex
# Version target: v0.1.0-beta → HEAD (main)
# ================================================================
#
# This file is the authoritative instruction set for ALL Codex agents
# working inside the cvsz/zcodex repository. Read every section before
# taking any action. Rules here override general Codex defaults.
#
# ================================================================

## 1. REPOSITORY IDENTITY

- **Name**: zcodex
- **Purpose**: Minimal, auditable Ubuntu bootstrapper for Codex CLI environments.
- **Primary language**: Bash (97 %), with Python helpers and a Makefile.
- **Supported targets**: Ubuntu 22.04 LTS, Ubuntu 24.04 LTS — `amd64` and `arm64`.
- **Main entry point**: `codex.sh` (orchestrator). Never modify its public mode API
  (`basic | full | ultimate | orchestrator | release`) without a ROADMAP entry.
- **Release cadence**: semver tags (`vX.Y.Z`). `VERSION` file is the single source of truth.

---

## 2. CRITICAL CONSTRAINTS — NEVER VIOLATE

1. **No `curl | bash`**. Downloads must go through `safe_download()` in
   `scripts/lib/installer.sh`. Every downloaded binary must be SHA-256 verified
   before execution.
2. **No plain `rm -rf`**. Use trap-protected `mktemp -d` workspaces. Paths must
   be scoped to `${WORK_DIR}` or `${HOME}/.zcodex/backups/`.
3. **No hardcoded secrets**. GITHUB_TOKEN, OPENAI_API_KEY, and any credential must
   come from environment variables only. Never write them to files, logs, or echo them.
4. **No monolithic scripts**. New logic goes into `scripts/lib/` as a sourced library.
   `codex.sh` and `scripts/install-codex-ubuntu.sh` are orchestrators only.
5. **No skipping ShellCheck**. Every `.sh` and `.bash` file must pass
   `shellcheck --shell=bash --severity=warning`. Disable directives require a comment.
6. **No force-pushes to `main`**. Branch protection is assumed. All changes go through
   feature branches and PRs.
7. **No changing `approval-policy` or `sandbox-mode`** in Codex config without
   an explicit security review note in the PR description.

---

## 3. AGENT OPERATING MODES

Codex agents must infer their operating mode from context and behave accordingly.

### 3.1 `READ` mode — exploration / analysis
- Read files, grep, and summarize. No writes, no installs, no git commits.
- Use `bash -n` to syntax-check before proposing changes.
- Always read `CHANGELOG.md`, `ROADMAP.md`, and `docs/architecture.md`
  before making structural suggestions.

### 3.2 `PATCH` mode — single-file fix
- Touch only the file(s) explicitly scoped in the task description.
- Run `shellcheck` and `shfmt -d` on every modified file before committing.
- Commit message format: `fix(<scope>): <what and why>` (conventional commits).

### 3.3 `FEATURE` mode — new functionality
- Create a feature branch: `git checkout -b feat/<short-name>`.
- Add or update Bats tests in `tests/` for every new code path.
- Update `docs/` if the feature changes architecture, capabilities, or state.
- Update `CHANGELOG.md` under `## [Unreleased]`.
- Open a PR with the checklist from `CONTRIBUTING.md`.

### 3.4 `RELEASE` mode — version cut
- Bump `VERSION`, tag `CHANGELOG.md`, run `make release-checksum`.
- Verify the artifact is reproducible: rebuild and diff SHA256SUMS.
- Tag only after CI is green: `git tag vX.Y.Z && git push origin vX.Y.Z`.

### 3.5 `DEBUG` mode — diagnosing failures
- Start with `bash scripts/doctor.sh` and read its output fully before acting.
- For CI failures, read the workflow YAML in `.github/workflows/` first.
- Prefer `--dry-run` flags when re-running installer steps to avoid side effects.

---

## 4. CODEBASE MAP — WHERE THINGS LIVE

```bash
zcodex/
├── codex.sh                     ← Orchestrator entry. Mode dispatch only.
├── VERSION                      ← Version source of truth. Single line: X.Y.Z
├── Makefile                     ← Developer shortcuts (lint, fmt-check, test, doctor, validate, release)
│
├── scripts/
│   ├── install-codex-ubuntu.sh  ← Main installer. Calls lib/* helpers.
│   ├── doctor.sh                ← Health-check and repair tool.
│   ├── validate-environment.sh  ← Pre-flight environment validator.
│   ├── e2e-runner.sh            ← E2E scenario plan runner (dry-run safe).
│   └── lib/
│       ├── runtime.sh           ← runtime_exec_logged, runtime_command_exists
│       ├── exec.sh              ← Low-level exec primitives sourced by codex.sh
│       ├── installer.sh         ← safe_download, safe_extract_tar, install phases
│       ├── platform.sh          ← OS/arch detection, capability probes
│       └── security.sh          ← Checksum, tempfile, lockfile, rollback helpers
│
├── tests/
│   ├── *.bats                   ← Bats unit tests. One file per lib module.
│   └── helpers/
│       └── *.bash               ← Shared Bats setup helpers.
│
├── config/zcodex/
│   └── config.toml              ← Canonical installer config example.
│
├── .codex/
│   └── AGENTS.md                ← THIS FILE. Agent instruction set.
│
├── .github/workflows/
│   ├── ci.yml                   ← Lint, ShellCheck, shfmt, Bats, E2E plan, security.
│   ├── e2e.yml                  ← Containerized Ubuntu 22.04/24.04 amd64+arm64.
│   ├── release-validate.yml     ← VERSION, tag, changelog, artifact reproducibility.
│   └── release.yml              ← Tag-only: deterministic archive + GitHub Release.
│
└── docs/
    ├── architecture.md
    ├── runtime.md
    ├── capabilities.md
    ├── manifest-state.md
    ├── infrastructure-hardening.md
    ├── release.md
    ├── release-checklist.md
    └── troubleshooting.md
```

---

## 5. CODING STANDARDS

### 5.1 Shell style
- Shebang: `#!/usr/bin/env bash`
- Header: `set -Eeuo pipefail` (orchestrators) or `set -euo pipefail` (libs with `IFS=$'\n\t'`).
- Indent: 2 spaces. No tabs. Enforced by `shfmt -i 2`.
- Line length: ≤ 100 characters.
- Quote all variable expansions: `"${var}"` not `$var`.
- Use `[[ ]]` for conditionals, not `[ ]`.
- Declare locals: `local var="value"` inside functions.
- Use `readonly` for constants defined at module scope.
- No `eval`. No `exec` outside of `scripts/lib/exec.sh` primitives.
- Prefer `printf` over `echo` for anything that might contain escape sequences.

### 5.2 Naming
- Functions: `snake_case` with a module prefix, e.g. `installer_download_node`.
- Constants: `UPPER_SNAKE_CASE` with `readonly`.
- Temp directories: always via `mktemp -d` and cleaned up in a `trap`.

### 5.3 Error handling
- Every fallible operation must either propagate the error or handle it explicitly.
- Use `|| { err "message"; return 1; }` pattern — never silent failures.
- Provide rollback paths for file writes and package installs.

### 5.4 Logging
- Use `log()`, `ok()`, `warn()`, `err()` from `scripts/lib/runtime.sh`.
- All output going to log files must pass through `redact_secrets()`.
- Never log raw environment variable values.

---

## 6. TESTING REQUIREMENTS

Every code change requires corresponding test coverage:

| Change type | Required test |
|---|---|
| New lib function | Bats unit test in `tests/<module>.bats` |
| New installer phase | Bats integration test + E2E plan update |
| New CLI flag | `--dry-run` path test + help text test |
| Security primitive | Negative test (should-fail path) required |
| Bug fix | Regression test proving the bug is fixed |

Running tests locally:
```bash
make test          # bats tests/
make lint          # shellcheck + bash -n
make fmt-check     # shfmt -d
make doctor        # scripts/doctor.sh --offline
make validate      # scripts/validate-environment.sh
```

Full suite before any PR:
```bash
make lint && make fmt-check && make test && make doctor && make validate
```

---

## 7. GIT WORKFLOW

### Branch naming
```bash
feat/<short-description>     # new features
fix/<short-description>      # bug fixes
docs/<short-description>     # documentation only
chore/<short-description>    # tooling, CI, formatting
release/vX.Y.Z               # release prep
```

### Commit messages (conventional commits)
```bash
<type>(<scope>): <imperative description>

[optional body explaining WHY]

[optional footer: Closes #<issue>]
```

Types: `feat`, `fix`, `docs`, `chore`, `test`, `ci`, `refactor`, `security`
Scope: `installer`, `doctor`, `lib`, `ci`, `config`, `docs`, `release`

### PR checklist (must pass before merge)
- [ ] `make lint` passes (ShellCheck + bash -n)
- [ ] `make fmt-check` passes (shfmt)
- [ ] `make test` passes (Bats)
- [ ] `make doctor` passes (offline)
- [ ] `CHANGELOG.md` updated under `## [Unreleased]`
- [ ] `docs/` updated if architecture or behaviour changed
- [ ] No hardcoded secrets, no world-writable paths, no plain `rm -rf`
- [ ] Dry-run tested manually: `CI=true bash codex.sh basic --dry-run --skip-docker`

---

## 8. SECURITY RULES FOR AGENTS

1. **Checksum all downloads**. Use `scripts/lib/security.sh:verify_sha256()`.
   Checksums live in `checksums.txt` — never inline them as string literals.

2. **Tempfiles are disposable**. Create with `mktemp -d`, register a cleanup trap
   immediately, never reuse across function boundaries.

3. **Lockfiles prevent concurrent runs**. Use `flock` from `scripts/lib/security.sh`.
   Never remove lock files manually; use the registered cleanup trap.

4. **Backups before overwrites**. Any config or profile file being rewritten must
   first be copied to `${HOME}/.zcodex/backups/<timestamp>/` preserving its path.

5. **Rollback on failure**. Every installer phase must register a rollback handler.
   Failures must restore the pre-install state and exit non-zero.

6. **Minimal Codex config**. The generated `~/.codex/config.toml` intentionally
   contains only `model`, `approval-policy`, and `sandbox-mode`. Do not expand it.

7. **No remote execution patterns**. Forbidden: `curl URL | bash`, `wget -O- | sh`,
   `eval "$(curl ...)"`. Always download → verify → execute as three separate steps.

8. **Secrets redaction in logs**. Apply `redact_secrets()` to any log stream that
   could contain `GITHUB_TOKEN`, `OPENAI_API_KEY`, or other credential patterns.

---

## 9. ENVIRONMENT VARIABLES

| Variable | Required | Description |
|---|---|---|
| `GITHUB_TOKEN` | Yes | GitHub API auth for gh CLI and release workflows |
| `OPENAI_API_KEY` | Yes | OpenAI API access for Codex CLI |
| `ZCODEX_RELEASE_LOG` | No | Override default release log path |
| `LOG_FILE` | No | Fallback log path (used by lib/runtime.sh) |
| `CI` | No | Set to `true` in CI environments; enables non-interactive mode |
| `TMPDIR` | No | Fallback temp dir base (default: `/tmp`) |

Agents must **never print** these values. Check presence only with `[ -n "${VAR:-}" ]`.

---

## 10. CODEX CLI CONFIG (generated by installer)

The installer writes a minimal `~/.codex/config.toml`:

```toml
model = "codex-mini-latest"

approval-policy = "on-request"
sandbox-mode = "workspace-write"
```

- `approval-policy = "on-request"` means the agent asks before shell commands.
  Do not change to `"never"` without an explicit security justification.
- `sandbox-mode = "workspace-write"` restricts writes to the workspace.
  Do not change to `"disable"` in production environments.

---

## 11. INSTALLER MODES (codex.sh dispatch)

| Mode | What it does | When to use |
|---|---|---|
| `basic` | Runs installer only | Quick setup on a known-good host |
| `full` | Installer + offline doctor | Standard developer setup |
| `ultimate` | Validate env + installer + online doctor | Fresh machine or CI first run |
| `orchestrator` | Doctor only | Repair / health-check existing installs |
| `release` | Installer + online doctor | Pre-release gate |

Preferred flags for Codex agent tasks:
```bash
# Safe exploration — never touches real state
CI=true bash codex.sh basic --dry-run --skip-docker --skip-optional

# E2E plan validation without Docker
bash scripts/e2e-runner.sh --dry-run --ubuntu 24.04 --arch amd64

# Repair existing install
bash scripts/doctor.sh --repair
```

---

## 12. AGENT TASK EXECUTION PROTOCOL

Before starting any task, the agent MUST:

1. **Read this file** in full.
2. **Determine the mode** (READ / PATCH / FEATURE / RELEASE / DEBUG).
3. **Check current branch**: `git branch --show-current`.
4. **Run a dry-run probe** to confirm the environment is sane:
   ```bash
   CI=true bash codex.sh basic --dry-run --skip-docker --skip-optional 2>&1 | tail -20
   ```
5. **Read relevant lib files** before modifying them.
6. **Run tests before and after** any code change.

After completing a task, the agent MUST:

1. Run the full local suite: `make lint && make fmt-check && make test`.
2. Verify no secrets are present in modified files: `git diff HEAD | grep -Ei 'ghp_|sk-|token|password'`.
3. Summarise changes in the commit body explaining the **why**, not just the what.
4. Update `CHANGELOG.md` if the change is user-visible.

---

## 13. OUT-OF-SCOPE — DO NOT DO

- Do not add runtime dependencies that are not available on stock Ubuntu 22.04/24.04.
- Do not add Docker as a hard requirement. It is always optional.
- Do not add Python as a hard requirement for the installer path. Python helpers are optional.
- Do not implement a web UI, REST API, or database.
- Do not modify `.github/workflows/release.yml` to disable the reproducibility gate.
- Do not merge changes that break arm64 compatibility.
- Do not introduce GPL-licensed code (project is MIT).

---

## 14. QUICK REFERENCE COMMANDS

```bash
# Lint + format check
make lint && make fmt-check

# Run all tests
make test

# Full local validation
make lint && make fmt-check && make test && make doctor && make validate

# Dry-run installer
CI=true bash codex.sh ultimate --dry-run --skip-docker

# Health check
bash scripts/doctor.sh

# Offline health check
bash scripts/doctor.sh --offline

# Repair
bash scripts/doctor.sh --repair

# Release dry-run
make release && make release-checksum

# ShellCheck single file
shellcheck --shell=bash scripts/lib/installer.sh

# shfmt check single file
shfmt -d scripts/lib/installer.sh

# Run single Bats test file
bats tests/installer.bats
```
