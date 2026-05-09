# Deep Repository Reconnaissance (cvsz/zcodex)

Date: 2026-05-09

## Stack & Structure Detection

- **Languages:** Bash (primary), Python (workflow policy helper), Markdown/TOML/YAML (config + docs + CI), SVG assets.
- **Frameworks:** No web framework; CLI installer architecture with Bash library modules.
- **Package managers:** `apt` (Ubuntu packages), `npm` (Codex CLI runtime), `pip` not used for app runtime.
- **Monorepo:** No; single-repo, single-product layout.
- **Services/apps:**
  - `scripts/install-codex-ubuntu.sh` (installer app entrypoint)
  - `scripts/doctor.sh` / `scripts/doctor-ci.sh` (health/repair service scripts)
  - `scripts/e2e-runner.sh` (scenario execution service)
  - `scripts/release.sh` + `scripts/build-release.sh` (release service)
  - `codex.sh` (meta-orchestrator app)
- **APIs:** No internal HTTP API. External API usage via GitHub Actions integrations and package registries (apt repos, npm registry).
- **Databases:** None (no RDBMS/NoSQL drivers or schemas).
- **Queues:** None (no MQ dependency).
- **Containers:** Docker used for E2E execution and optional runtime checks.
- **Orchestration:** GitHub Actions workflows + `Makefile` targets.
- **IaC:** Shell-based host bootstrap and CI workflow definitions; no Terraform/Pulumi/CloudFormation.
- **Generated files:** `dist/`, `artifacts/`, diagnostics bundles, reproducibility outputs (`dist-a`, `dist-b`, `dist.repro-*`).
- **Binaries in repo:** test fixture binaries under `tests/runtime-fixtures/**/bin/*` (mocked command shims).
- **Vendored dependencies:** none obvious; no `vendor/` tree.
- **Test frameworks:** Bats, ShellCheck, shfmt checks, Python policy script.
- **Build systems:** GNU Make + shell scripts.
- **Release systems:** scripted deterministic tarball build + checksum verification + GitHub Releases workflow.

## Architecture Map

```text
operator / CI
  -> codex.sh (workflow chooser)
      -> scripts/install-codex-ubuntu.sh
          -> scripts/lib/runtime.sh
              -> scripts/lib/{environment,exec,context,logging,retry,platform,security,pins,state,backup,packages,nodejs,docker,codex,shell,manifest,installer}.sh
      -> scripts/doctor.sh, scripts/diagnostics.sh
      -> scripts/release.sh -> scripts/build-release.sh -> dist/*.tar.gz + SHA256SUMS

GitHub Actions (.github/workflows/*.yml)
  -> make validate / script entrypoints
  -> artifact upload + release publication
```

## Runtime Dependency Graph

1. Entrypoints (`codex.sh`, installer, doctor, release scripts)
2. Runtime loader (`scripts/lib/runtime.sh`)
3. Domain libs (security, platform, packages, nodejs, docker, codex)
4. OS tooling (`bash`, `apt-get`, `sudo`, `tar`, `gzip`, `sha256sum`, `git`, `curl`, `npm`, optional `docker`)
5. External distribution channels (Ubuntu apt repos, npm registry, GitHub Actions runners/artifacts)

## Service Graph

- **Install path:** `codex.sh`/manual invocation -> installer entrypoint -> shared libs -> package/runtime mutation.
- **Validation path:** Make/CI -> lint/format/test/e2e-dry-run -> diagnostics on failure.
- **Release path:** release validation -> deterministic archive build -> checksum verification -> release workflow publish.

## Trust Boundaries

1. **Local operator shell** vs **privileged host mutation (`sudo`, package install)**.
2. **Repository code** vs **network-fetched packages/artifacts**.
3. **CI ephemeral runner** vs **persisted release artifacts**.
4. **System runtime ownership checks** vs **pre-existing host-managed runtimes (nvm/asdf/NodeSource/apt)**.

## Attack Surface Inventory

- Shell script argument parsing and environment-variable handling.
- Privileged package installation and runtime path mutation.
- PATH/command resolution for `node`, `npm`, `codex`, `sudo`.
- Shell profile writes and configuration directory permissions.
- CI workflows that execute project scripts on PR/push.
- Artifact generation + checksum publication chain.

## Risky Module Inventory

- `scripts/lib/security.sh` (guardrails correctness is security-critical).
- `scripts/lib/exec.sh` and `scripts/lib/retry.sh` (command execution wrappers).
- `scripts/lib/packages.sh` / `nodejs.sh` (network + package mutation).
- `scripts/lib/installer.sh` (phase sequencing and failure-state correctness).
- `scripts/release.sh` / `build-release.sh` (supply-chain integrity path).

## Privileged Execution Paths

- Installer and doctor flows invoking `sudo apt-get` and system package operations.
- Docker installation/validation path (group membership / daemon interaction).
- Release and validation commands that write system/user state and build artifacts.

## External Integrations

- GitHub Actions (`actions/checkout`, `actions/upload-artifact`, third-party actions like Trivy and gitleaks).
- Ubuntu apt repositories.
- npm registry for Codex CLI runtime.
- Docker ecosystem when enabled.

## Network Topology Assumptions

- Outbound internet required for apt/npm and CI action pulls.
- DNS + HTTPS egress to GitHub, Ubuntu mirrors, npm registry.
- No inbound ports/services exposed by repository itself.

## Environment Variable Inventory (Observed/Implied)

- Locale/time: `LC_ALL`, `LANG`, `TZ`.
- Install/runtime paths: `HOME`, `TMPDIR`, `XDG_*`.
- npm paths/cache: `npm_config_cache`, `NPM_CONFIG_CACHE`, `npm_config_prefix`, `NPM_CONFIG_PREFIX`.
- CI controls: `CI`, `DEBIAN_FRONTEND`, `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24`.
- Script/runtime vars: `LOG_FILE`, `ZCODEX_*` namespaced variables.

## Secret Exposure Risk Inventory

- CI logs may expose command-line arguments or environment if debugging is verbose.
- Diagnostics artifact collection may capture sensitive host metadata if not redacted.
- Shell profile/state/manifest files in user home can expose operational details.
- GitHub token use is constrained in workflows, but third-party actions remain supply-chain risk.

---

## 1) High-Risk Areas

- Privileged package/runtime mutation paths (`apt`, npm global install, docker setup).
- Command lookup/PATH safety enforcement and shadowing detection.
- Release artifact reproducibility and checksum correctness chain.
- CI third-party action trust and pinned-version hygiene.

## 2) Critical Execution Paths

1. Installer phase machine: validate -> download -> verify -> install -> configure -> verify-runtime -> complete/failed.
2. Runtime ownership classification before mutation (`node`/`npm`/`codex`).
3. Release build + checksum verification before publish.
4. Doctor/repair path for interrupted or stale states.

## 3) Most Fragile Modules

- `scripts/lib/installer.sh` (cross-module orchestration complexity).
- `scripts/lib/platform.sh` and runtime ownership logic (host variability).
- `scripts/e2e-runner.sh` (container/host matrix variance).
- CI workflow policy and reproducibility checks (toolchain drift sensitivity).

## 4) Missing Protections (Potential Gaps)

- No typed language/static contracts for runtime behavior (Bash footgun exposure).
- Limited isolation from third-party GitHub Actions supply-chain changes.
- No first-class SBOM/signature attestation workflow observed.
- No centralized secret-scrubbing policy for all diagnostics artifacts observed.

## 5) Dependency Risks

- apt mirror/package volatility across Ubuntu images.
- npm ecosystem risk for globally installed CLI dependencies.
- Docker availability and permission model variance across hosts.
- CI tool version drift (bash/shellcheck/shfmt/bats/action versions).

## 6) Technical Debt Hotspots

- Large Bash surface area across many libraries.
- Duplication risk between orchestrator scripts and lib wrappers.
- Extensive fixture matrix maintenance burden under `tests/runtime-fixtures`.
- Documentation/report sprawl increases consistency maintenance load.
