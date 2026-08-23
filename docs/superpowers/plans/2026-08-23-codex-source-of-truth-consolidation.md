# Codex Source-of-Truth Consolidation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `cvsz/zcodex` a reproducible integration source of truth containing pinned, attributable Git-subtree imports of the four public OpenAI Codex repositories.

**Architecture:** Preserve the current repository as the integration/control plane and isolate upstream sources below `components/`. A JSON-compatible YAML manifest drives fail-closed validation, provenance checks, cross-platform update commands, CI, and release inventory; upstream changes always enter through reviewable branches and pull requests.

**Tech Stack:** Git subtrees, Bash 4+, PowerShell 7+, Python 3 standard library, Bats, GitHub Actions, existing ShellCheck/shfmt/release tooling.

**Spec:** `docs/superpowers/specs/2026-08-23-codex-source-of-truth-design.md`

## Global Constraints

- Preserve all existing root-level assets and Git history.
- Track only `https://github.com/openai/codex.git`, `https://github.com/openai/skills.git`, `https://github.com/openai/plugins.git`, and `https://github.com/openai/codex-universal.git`.
- Import into `components/codex`, `components/skills`, `components/plugins`, and `components/codex-universal`.
- Use Git subtrees; do not use submodules or flatten upstream files into the root.
- Never push upstream updates directly to `main`, force-push, or silently resolve conflicts.
- Treat upstream content as untrusted until repository identity, commit reachability, path containment, and licenses pass validation.
- Retain upstream license files and record repository, branch, commit SHA, and license metadata.
- Local modifications belong under `integration/patches/<component>/` or `integration/compatibility/`, never as undocumented subtree edits.
- Linux and Windows update entry points must implement the same contract.
- Each component import is a separate reviewable commit/PR.
- No release is valid unless manifest, provenance, integration, security, reproducibility, and license gates pass.

---

## File Map

- `UPSTREAMS.yaml`: JSON-compatible YAML manifest containing pinned upstream identity and policy.
- `schemas/upstreams.schema.json`: exact manifest contract.
- `scripts/upstream/manifest.py`: standard-library manifest loader and validator.
- `scripts/upstream/check_tree.py`: path containment, symlink, license, and provenance validation.
- `scripts/upstream/update.sh`: Linux/macOS prepare/check/import/update entry point.
- `scripts/upstream/update.ps1`: Windows PowerShell contract-equivalent entry point.
- `scripts/upstream/source_inventory.py`: deterministic release inventory generator.
- `tests/upstream_manifest.bats`: manifest validation regression tests.
- `tests/upstream_tree.bats`: unsafe-tree and license regressions.
- `tests/upstream_update.bats`: update command safety and dry-run regressions.
- `tests/fixtures/upstreams/`: local bare repositories and malformed manifests; tests never depend on mutable network state.
- `.github/workflows/upstream-validate.yml`: PR validation with path-aware component gates.
- `.github/workflows/upstream-sync.yml`: scheduled/manual detection and update-PR creation.
- `docs/upstream/OPERATIONS.md`: operator workflow and recovery.
- `docs/upstream/LICENSES.md`: generated attribution inventory.
- `integration/patches/README.md`: patch naming and application policy.
- `integration/compatibility/README.md`: adapter ownership rules.
- `Makefile`: local validation/update/inventory targets.
- `scripts/build-release.sh` and `scripts/verify-release-artifacts.sh`: include and verify upstream inventory.

### Task 1: Lock the Manifest Contract

**Files:**
- Create: `UPSTREAMS.yaml`
- Create: `schemas/upstreams.schema.json`
- Create: `scripts/upstream/manifest.py`
- Create: `tests/upstream_manifest.bats`
- Create: `tests/fixtures/upstreams/invalid-url.yaml`
- Create: `tests/fixtures/upstreams/invalid-prefix.yaml`
- Modify: `Makefile`

**Interfaces:**
- Produces: `load_manifest(path: pathlib.Path) -> dict`, `validate_manifest(data: dict) -> list[str]`, CLI `python3 scripts/upstream/manifest.py validate [PATH]`.
- Manifest keys: `version`, `components[].name`, `repository`, `branch`, `prefix`, `commit`, `license.spdx`, `license.path`, `patches`, `update_policy`.

- [ ] **Step 1: Write failing Bats coverage**

Create tests asserting the canonical manifest validates, an unapproved GitHub URL fails with `repository is not allowlisted`, `../` in a prefix fails with `prefix must be components/<name>`, and a non-40-character lowercase hexadecimal commit fails.

- [ ] **Step 2: Run the focused test**

Run: `bats tests/upstream_manifest.bats`  
Expected: FAIL because `scripts/upstream/manifest.py` does not exist.

- [ ] **Step 3: Add the manifest and validator**

Make `UPSTREAMS.yaml` JSON syntax so it remains valid YAML 1.2 and can be parsed with Python's `json` module without a new dependency. Initialize all four entries with their allowlisted URL, tracked default branch verified at import time, exact prefix, 40-zero placeholder commit, license fields, empty patch list, and `update_policy: pull_request`. The validator must reject the zero commit outside the explicit `--allow-unimported` bootstrap mode.

- [ ] **Step 4: Add schema and Make target**

Add `upstream-manifest` to `.PHONY` and implement:

```make
upstream-manifest:
	python3 scripts/upstream/manifest.py validate UPSTREAMS.yaml
```

- [ ] **Step 5: Verify red/green behavior**

Run: `bats tests/upstream_manifest.bats && python3 scripts/upstream/manifest.py validate --allow-unimported UPSTREAMS.yaml`  
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add UPSTREAMS.yaml schemas/upstreams.schema.json scripts/upstream/manifest.py tests/upstream_manifest.bats tests/fixtures/upstreams Makefile
git commit -m "feat(upstream): define pinned source manifest"
```

### Task 2: Enforce Tree, License, and Provenance Safety

**Files:**
- Create: `scripts/upstream/check_tree.py`
- Create: `tests/upstream_tree.bats`
- Create: `tests/fixtures/upstreams/safe-tree/LICENSE`
- Create: `tests/fixtures/upstreams/escaping-link`
- Modify: `Makefile`

**Interfaces:**
- Consumes: `load_manifest()` and `validate_manifest()`.
- Produces CLI:
  - `check_tree.py paths COMPONENT ROOT`
  - `check_tree.py license COMPONENT ROOT`
  - `check_tree.py provenance COMPONENT ROOT`
  - `check_tree.py all COMPONENT ROOT`

- [ ] **Step 1: Write failing safety tests**

Cover: missing component prefix, missing declared license, absolute symlink, relative symlink escaping the prefix, clean contained symlink, unknown component, and provenance mismatch between manifest commit and the `git-subtree-split` trailer of the most recent prefix commit.

- [ ] **Step 2: Confirm expected failure**

Run: `bats tests/upstream_tree.bats`  
Expected: FAIL because `check_tree.py` is absent.

- [ ] **Step 3: Implement fail-closed checks**

Use `pathlib.Path.resolve(strict=False)` plus `os.path.commonpath` for containment. Walk with `os.scandir` without following directory symlinks. Reject absolute links and any resolved target outside the component root. Read provenance from `git log --format=%B --max-count=1 -- <prefix>` and require exactly one `git-subtree-split: <manifest SHA>` trailer.

- [ ] **Step 4: Wire the aggregate target**

Add:

```make
upstream-validate: upstream-manifest
	@for component in codex skills plugins codex-universal; do \
		python3 scripts/upstream/check_tree.py all "$$component" .; \
	done
```

Do not add `upstream-validate` to the existing global `validate` target until the first component import is complete.

- [ ] **Step 5: Run tests and static checks**

Run: `bats tests/upstream_tree.bats && python3 -m py_compile scripts/upstream/manifest.py scripts/upstream/check_tree.py`  
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add scripts/upstream/check_tree.py tests/upstream_tree.bats tests/fixtures/upstreams Makefile
git commit -m "feat(upstream): validate tree safety and provenance"
```

### Task 3: Add Cross-Platform Update Preparation

**Files:**
- Create: `scripts/upstream/update.sh`
- Create: `scripts/upstream/update.ps1`
- Create: `tests/upstream_update.bats`
- Create: `tests/fixtures/upstreams/create-local-remotes.sh`
- Modify: `Makefile`

**Interfaces:**
- Produces identical commands on both platforms:
  - `list`
  - `check --component NAME`
  - `import --component NAME --commit SHA`
  - `update --component NAME --commit SHA`
  - `--dry-run`
- Exit codes: `0` success/no drift, `2` usage, `3` dirty worktree, `4` identity/commit failure, `5` subtree conflict, `6` validation failure.

- [ ] **Step 1: Write failing contract tests**

Using local bare remotes, assert: unknown component is rejected; dirty worktree is rejected; `--dry-run` prints but does not execute a subtree command; a commit not reachable from the configured branch is rejected; import refuses an existing prefix; update refuses a missing prefix; the command never changes `main` directly.

- [ ] **Step 2: Verify failure**

Run: `bats tests/upstream_update.bats`  
Expected: FAIL because the update entry points are missing.

- [ ] **Step 3: Implement Bash entry point**

Use arrays for every Git command, `mktemp -d`, a trap for cleanup, `git status --porcelain=v1`, exact allowlisted remotes from the manifest, and `git merge-base --is-ancestor SHA refs/remotes/<temporary>/<branch>`. Invoke `git subtree add` or `git subtree pull` without `--squash` to preserve history. Never invoke `eval`.

- [ ] **Step 4: Implement PowerShell parity**

Use `[System.IO.Path]::GetFullPath`, argument arrays, `try/finally` cleanup, `$LASTEXITCODE` checks, and `& git @args`. Do not use `Invoke-Expression`. Emit the same exit codes and dry-run command representation as Bash.

- [ ] **Step 5: Add local Make targets**

```make
upstream-list:
	bash scripts/upstream/update.sh list

upstream-check:
	bash scripts/upstream/update.sh check --component "$(COMPONENT)"

upstream-import:
	bash scripts/upstream/update.sh import --component "$(COMPONENT)" --commit "$(COMMIT)"
```

- [ ] **Step 6: Verify both entry points**

Run: `bats tests/upstream_update.bats && shellcheck scripts/upstream/update.sh && pwsh -NoProfile -File scripts/upstream/update.ps1 list`  
Expected: PASS with four manifest entries printed by both implementations.

- [ ] **Step 7: Commit**

```bash
git add scripts/upstream/update.sh scripts/upstream/update.ps1 tests/upstream_update.bats tests/fixtures/upstreams Makefile
git commit -m "feat(upstream): add safe cross-platform synchronization"
```

### Task 4: Import the Four Upstreams as Independent Changes

**Files:**
- Create: `components/codex/**`
- Create: `components/skills/**`
- Create: `components/plugins/**`
- Create: `components/codex-universal/**`
- Modify: `UPSTREAMS.yaml`
- Create: `integration/patches/README.md`
- Create: `integration/compatibility/README.md`

**Interfaces:**
- Consumes: update commands and validators from Tasks 1–3.
- Produces: four subtree prefixes whose latest import commits carry `git-subtree-dir` and `git-subtree-split` trailers matching the manifest.

- [ ] **Step 1: Record immutable candidate SHAs**

Run `git ls-remote <allowlisted-url> refs/heads/<tracked-branch>` for each component. Record the exact 40-character SHA before importing. Verify each commit with the update command's reachability check.

- [ ] **Step 2: Import `openai/codex`**

Run: `bash scripts/upstream/update.sh import --component codex --commit <recorded-codex-sha>`  
Expected: `components/codex` exists, its license validates, and `UPSTREAMS.yaml` pins the recorded SHA.

Commit only this component:

```bash
git add components/codex UPSTREAMS.yaml
git commit -m "vendor(codex): import pinned upstream subtree"
```

- [ ] **Step 3: Import `openai/skills`**

Use the same verified flow for `skills`, then commit only `components/skills` and `UPSTREAMS.yaml` with `vendor(skills): import pinned upstream subtree`.

- [ ] **Step 4: Import `openai/plugins`**

Use the same verified flow for `plugins`, then commit only `components/plugins` and `UPSTREAMS.yaml` with `vendor(plugins): import pinned upstream subtree`.

- [ ] **Step 5: Import `openai/codex-universal`**

Use the same verified flow for `codex-universal`, then commit only `components/codex-universal` and `UPSTREAMS.yaml` with `vendor(codex-universal): import pinned upstream subtree`.

- [ ] **Step 6: Establish local-change policy**

Document patch filenames as `NNNN-<component>-<summary>.patch`, require a metadata header containing upstream base SHA and purpose, and require adapters to expose their supported component SHA ranges.

- [ ] **Step 7: Run the aggregate gate**

Run: `make upstream-validate && make validate`  
Expected: PASS, with all four manifests, licenses, paths, and provenance trailers verified.

### Task 5: Generate Deterministic Source and License Inventories

**Files:**
- Create: `scripts/upstream/source_inventory.py`
- Create: `tests/upstream_inventory.bats`
- Create: `docs/upstream/LICENSES.md`
- Create: `dist-manifest/.gitkeep`
- Modify: `scripts/build-release.sh`
- Modify: `scripts/verify-release-artifacts.sh`
- Modify: `Makefile`

**Interfaces:**
- Produces: `source_inventory.py --format json|markdown --output PATH`.
- JSON fields: `schema_version`, `integration_version`, `generated_at` fixed from `SOURCE_DATE_EPOCH`, and sorted `components` containing name, repository, branch, commit, prefix, SPDX license, license SHA-256, patch IDs, and tree SHA-256.

- [ ] **Step 1: Write failing determinism tests**

Run inventory twice with identical `SOURCE_DATE_EPOCH`; assert byte-identical JSON and Markdown. Change one component file; assert only that component's tree hash changes. Remove a license; assert exit `6`.

- [ ] **Step 2: Verify failure**

Run: `bats tests/upstream_inventory.bats`  
Expected: FAIL because the generator is absent.

- [ ] **Step 3: Implement inventory generation**

Sort paths using bytewise UTF-8 order, hash file type/path/mode/content, hash symlink target text without following it, omit `.git`, and use compact sorted JSON. Generate `docs/upstream/LICENSES.md` from the same normalized data.

- [ ] **Step 4: Integrate releases**

Update the release builder to include `UPSTREAMS.yaml`, `SOURCE-INVENTORY.json`, and `THIRD-PARTY-LICENSES.md`. Update verification to regenerate and compare inventory, validate checksums, and fail on missing component licenses.

- [ ] **Step 5: Verify reproducibility**

Run: `bats tests/upstream_inventory.bats && make release-reproducible && make release-verify`  
Expected: PASS and byte-identical release archives.

- [ ] **Step 6: Commit**

```bash
git add scripts/upstream/source_inventory.py tests/upstream_inventory.bats docs/upstream/LICENSES.md dist-manifest scripts/build-release.sh scripts/verify-release-artifacts.sh Makefile
git commit -m "feat(release): add upstream source inventory"
```

### Task 6: Add Pull-Request Validation and Component Gates

**Files:**
- Create: `.github/workflows/upstream-validate.yml`
- Modify: `.github/workflows/ci.yml`
- Modify: `tests/workflow_policy.py`
- Modify: `scripts/check-action-versions.sh`

**Interfaces:**
- Produces required job names: `upstream / manifest`, `upstream / provenance`, `upstream / component-codex`, `upstream / component-skills`, `upstream / component-plugins`, `upstream / component-codex-universal`, and `upstream / aggregate`.

- [ ] **Step 1: Add failing workflow-policy assertions**

Require explicit `permissions: contents: read`, immutable action pins accepted by the repository policy, path classification covering the four prefixes plus shared integration files, no `pull_request_target`, and an always-running aggregate job that fails when any applicable component job fails.

- [ ] **Step 2: Run policy test**

Run: `python3 tests/workflow_policy.py`  
Expected: FAIL because `upstream-validate.yml` is missing.

- [ ] **Step 3: Implement workflow**

Run manifest/provenance/license checks on every relevant PR. Use path output to enable component jobs only for changes to its prefix, manifest entry, patch directory, compatibility adapters, or shared upstream tooling. Keep existing CI intact and make the existing aggregate validation depend on the new aggregate gate only after a green repository run.

- [ ] **Step 4: Run local validation**

Run: `python3 tests/workflow_policy.py && bash scripts/check-action-versions.sh && make validate`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/upstream-validate.yml .github/workflows/ci.yml tests/workflow_policy.py scripts/check-action-versions.sh
git commit -m "ci: validate pinned upstream components"
```

### Task 7: Add Scheduled Update Pull Requests

**Files:**
- Create: `.github/workflows/upstream-sync.yml`
- Create: `scripts/upstream/open-update-pr.sh`
- Create: `tests/upstream_sync_policy.bats`
- Modify: `tests/workflow_policy.py`

**Interfaces:**
- Workflow inputs: optional `component` enum and `dry_run` boolean.
- Branch format: `automation/upstream-<component>-<12-char-sha>`.
- PR title: `vendor(<component>): update upstream to <12-char-sha>`.
- Labels: `dependencies`, `upstream-sync`, `<component>`.

- [ ] **Step 1: Write failing least-privilege tests**

Assert scheduled/manual triggers only, `contents: write` and `pull-requests: write` only at the update job, concurrency grouping, no force push, no direct push to `main`, branch names derived only from validated component/SHA, and no PR creation when validation fails or no drift exists.

- [ ] **Step 2: Confirm failure**

Run: `bats tests/upstream_sync_policy.bats && python3 tests/workflow_policy.py`  
Expected: FAIL because the sync workflow is absent.

- [ ] **Step 3: Implement the PR preparation script**

Require a clean checkout, validate the remote SHA, create the deterministic automation branch, call `update.sh update`, update the manifest, run `make upstream-validate`, commit, push without `--force`, and create a PR with the old/new SHAs and validation summary. If the branch already exists, stop with an actionable message rather than overwriting it.

- [ ] **Step 4: Implement the workflow**

Use a matrix of the four components for schedule runs and the selected component for manual runs. Set `timeout-minutes`, concurrency, minimal permissions, and upload only non-sensitive validation summaries on failure.

- [ ] **Step 5: Verify policy**

Run: `bats tests/upstream_sync_policy.bats && python3 tests/workflow_policy.py && shellcheck scripts/upstream/open-update-pr.sh`  
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add .github/workflows/upstream-sync.yml scripts/upstream/open-update-pr.sh tests/upstream_sync_policy.bats tests/workflow_policy.py
git commit -m "ci: prepare reviewed upstream update pull requests"
```

### Task 8: Document Operations, Recovery, and First Release Candidate

**Files:**
- Create: `docs/upstream/OPERATIONS.md`
- Create: `docs/upstream/PROVENANCE.md`
- Modify: `README.md`
- Modify: `ROADMAP.md`
- Modify: `SECURITY_ARCHITECTURE.md`
- Modify: `THREAT_MODEL.md`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Documents the exact commands from Tasks 1–7 and maps each acceptance criterion to a verification command.

- [ ] **Step 1: Document operator flows**

Include clone behavior, manifest reading, local check/import/update on Bash and PowerShell, update-PR review checklist, conflict recovery without force push, patch policy, rollback by reverting the component update commit, and release inventory verification.

- [ ] **Step 2: Update security documentation**

Add upstream compromise, malicious symlink/path, license disappearance, action compromise, provenance mismatch, and patch drift threats with their implemented controls and residual risks.

- [ ] **Step 3: Update project-facing documentation**

Explain that `cvsz/zcodex` is authoritative for the tested composition while each `openai/*` repository remains authoritative for its component. Clearly state that proprietary model weights, Codex cloud, and the IDE extension are not included.

- [ ] **Step 4: Run full verification**

Run:

```bash
make upstream-validate
make validate
make release-reproducible
make release-verify
git status --short
```

Expected: all commands PASS and the worktree is clean after committing generated documentation.

- [ ] **Step 5: Record the release candidate**

Update `CHANGELOG.md` with the four pinned SHAs, validation commands, inventory checksum, and remaining blockers. Do not tag or publish a release until every required GitHub check is green.

- [ ] **Step 6: Commit**

```bash
git add docs/upstream README.md ROADMAP.md SECURITY_ARCHITECTURE.md THREAT_MODEL.md CHANGELOG.md
git commit -m "docs: complete source-of-truth operations"
```

## Final Review Gate

Before merging the implementation PR:

- [ ] Confirm each subtree import is independently reviewable in history.
- [ ] Confirm `git clone https://github.com/cvsz/zcodex.git` contains all four source trees without submodule commands.
- [ ] Confirm the manifest SHA and subtree trailer match for every component.
- [ ] Confirm all license files and the combined inventory are present.
- [ ] Confirm Linux and PowerShell dry-run outputs agree.
- [ ] Confirm scheduled updates create PRs only and cannot update `main` directly.
- [ ] Confirm all existing `make validate` behavior remains green.
- [ ] Confirm reproducible release archives match byte-for-byte.
- [ ] Confirm no proprietary model weights, Codex cloud source, or IDE extension source is claimed or included.
