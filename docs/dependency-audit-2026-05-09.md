# Dependency Audit Report — 2026-05-09

## Scope
Repository: `cvsz/zcodex` (local path `/home/zeazdev/zcodex`)

## Inventory results
No first-party manifests were found for:
- npm / yarn / pnpm (`package.json`, lockfiles)
- pip / poetry (`requirements*.txt`, `pyproject.toml`, `poetry.lock`)
- cargo (`Cargo.toml`, `Cargo.lock`)
- Go modules (`go.mod`, `go.sum`)
- Maven / Gradle (`pom.xml`, `build.gradle*`)
- Docker image build definitions (`Dockerfile*`, `docker-compose*`)

Detected dependency surfaces:
- GitHub Actions workflows in `.github/workflows/*.yml`
- Ubuntu APT packages installed dynamically in CI/release workflows

## Task-by-task findings

### Build SBOM
- Implemented automated SBOM generation using `syft` in `.github/workflows/supply-chain.yml`.
- Output format: SPDX JSON (`artifacts/sbom.spdx.json`).

### Audit direct and transitive dependencies
- No language package manifests present, so no direct/transitive trees for npm/pip/cargo/go/maven ecosystems.
- Auditable direct dependencies currently are workflow actions and APT packages in CI scripts/workflows.

### Abandoned / unmaintained / vulnerable packages
- No package-manager lockfiles are present to evaluate abandonment/CVE posture for language ecosystems.
- GitHub Actions dependencies are versioned by major tag (e.g., `@v5`, `@v3`).

### Duplicate dependency trees
- Not applicable for npm/pip/cargo/go/maven due to absent manifests.

### Dependency confusion & typosquatting risk
- Not applicable for language registries in current repository state (no registry manifests).
- Residual risk remains if future manifests are introduced without pinned registries and source policies.

### Incompatible versions / lockfile corruption / non-deterministic installs
- No lockfiles found, so lockfile corruption/drift could not be evaluated.
- Existing CI installs APT packages at runtime; this is inherently mutable over time unless snapshots/pins are used.

## Fixes implemented in this change
1. Added Dependabot config for GitHub Actions + Docker ecosystem scanning.
2. Added Renovate config with lockfile maintenance and grouped dependency updates.
3. Added supply-chain workflow that:
   - generates SBOM,
   - creates and verifies checksum,
   - uploads artifact,
   - emits provenance attestation via `actions/attest-build-provenance`.

## Recommended next hardening steps
- Introduce a pinned Ubuntu snapshot or image digest strategy for CI to reduce APT nondeterminism.
- Add explicit policy checks for action digest pinning where feasible.
- If/when language manifests are introduced, enforce:
  - lockfiles in CI,
  - checksum-hardened installers,
  - registry allowlists,
  - automated `audit`/`osv`/SCA scans.
