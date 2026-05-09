# Dependency Audit & Upgrade Report — 2026-05-09

## Findings
- **Ecosystem manifests absent:** repository contains no first-party manifests for npm, pnpm, yarn, pip, poetry, cargo, or go modules (`package.json`, `pnpm-lock.yaml`, `yarn.lock`, `requirements*.txt`, `pyproject.toml`, `Cargo.toml`, `go.mod` are all absent).
- **SBOM path present:** SBOM generation is handled in CI via `.github/workflows/supply-chain.yml` (SPDX output).
- **Direct dependency surface:** GitHub Actions and Ubuntu apt packages installed in workflows.
- **Transitive dependency surface:** action sub-dependencies and apt dependency graph (managed upstream; not lockfile-controlled in repo).
- **Abandonment/vulnerability:** no language package graph exists to audit; action versions pass policy checks (`scripts/check-action-versions.sh`).
- **Duplicate trees:** not applicable without language manifests.
- **Lockfile drift risk:** potential future drift if manifests are added without lockfiles.
- **Incompatible upgrades:** no language runtime package upgrades were required in this repository state.

## Changes implemented
1. Added `scripts/check-lockfiles.sh` to enforce lockfile/pinning policy for future manifests.
2. Added `make lockfile-policy` target and integrated it into `make validate`.
3. Added CI enforcement step (`Enforce lockfile policy`) in `.github/workflows/ci.yml`.

## Migration notes
- If `package.json` is introduced, commit `package-lock.json` in same PR.
- If `pnpm-workspace.yaml` is introduced, commit `pnpm-lock.yaml`.
- If `pyproject.toml` is introduced for Poetry, commit `poetry.lock`.
- If `Cargo.toml` is introduced, commit `Cargo.lock`.
- If `go.mod` is introduced, commit `go.sum`.
- If `requirements.txt` is used, pin exact versions using `==`.

## Rollback strategy
- Revert commit that introduced lockfile policy wiring:
  - `git revert <commit_sha>`
- Or temporarily bypass in CI by removing `make lockfile-policy` step from `.github/workflows/ci.yml` and re-running pipeline.

## Side-effect validation
- `scripts/check-lockfiles.sh` is no-op/pass when no managed manifests exist.
- Existing workflow policy checks remain green.
- No runtime installer paths were modified.

## Benchmarks (before/after)
- Baseline for new policy check (run #1): `real 0m0.060s`
- Baseline for new policy check (run #2): `real 0m0.057s`
- Impact: negligible CI overhead (<0.1s local shell timing).

## Remaining risks
- Apt package versions in GitHub-hosted runners remain mutable over time.
- Action major tags can still drift between minor/patch releases unless fully SHA-pinned.
- No language-level lockfile integrity checks can run until manifests are introduced.
