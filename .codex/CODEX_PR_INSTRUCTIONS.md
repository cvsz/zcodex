# CODEX_PR_INSTRUCTIONS.md
# Repository: https://github.com/cvsz/zcodex
# Scope: Rules for every Pull Request opened by a Codex agent in this repo.
# ================================================================
#
# Read this file before opening any PR. Reviewers use this checklist
# to verify correctness, safety, and release-readiness.
#
# ================================================================

## 1. BRANCH REQUIREMENTS

Before opening a PR the agent must confirm:

```bash
# Must NOT be on main
git branch --show-current   # must not return "main"

# Branch must be pushed to origin
git push -u origin "$(git branch --show-current)"

# Branch must be up-to-date with main
git fetch origin main
git log --oneline HEAD..origin/main   # must be empty
```

Branch naming convention:
```
feat/<short-kebab-description>      # new capability
fix/<short-kebab-description>       # bug fix
security/<short-kebab-description>  # security hardening
docs/<short-kebab-description>      # docs only
chore/<short-kebab-description>     # tooling / CI
refactor/<short-kebab-description>  # internal restructure
test/<short-kebab-description>      # test coverage only
release/vX.Y.Z                      # release prep
```

---

## 2. MANDATORY CI GATE CHECKS (must be green before review request)

```bash
make lint        # shellcheck + bash -n on all .sh/.bash files
make fmt-check   # shfmt -d — zero diff expected
make test        # bats tests/ — all tests must pass
make doctor      # scripts/doctor.sh --offline
make validate    # scripts/validate-environment.sh
```

Dry-run the installer for any PR that touches `scripts/`:
```bash
CI=true bash codex.sh basic --dry-run --skip-docker --skip-optional 2>&1 | tail -30
```

For E2E-affecting changes:
```bash
bash scripts/e2e-runner.sh --dry-run --ubuntu 24.04 --arch amd64
```

**Do not open a PR if any gate is red.** Fix it first.

---

## 3. PR TITLE FORMAT

Same rules as commit subjects (Conventional Commits):

```
<type>(<scope>): <imperative subject ≤ 72 chars>
```

Examples:
```
feat(installer): add rootless Docker detection for non-sudo hosts
fix(security): close path traversal gap in safe_extract_tar
docs(runtime): document manifest state file schema
chore(ci): upgrade shellcheck action to v2.2.4
security(lib): enforce TLS certificate verification in safe_download
```

---

## 4. PR DESCRIPTION TEMPLATE

Use this exact structure. Every section is required.
Delete sections that genuinely do not apply and state why.

```markdown
## Summary

<!-- 2–4 sentences: what changed, why it changed, what it does NOT change. -->

## Motivation

<!-- The problem or gap this PR closes. Link to issue if one exists. -->

## Changes

<!-- Bullet list of files modified and what changed in each. -->

- `scripts/lib/security.sh` — added `verify_content_type()` guard in `safe_download`
- `tests/security.bats` — regression test for HTML error-page bypass scenario
- `docs/infrastructure-hardening.md` — documented Content-Type enforcement

## Test Evidence

<!-- Paste or describe the output of: make lint && make fmt-check && make test -->

```
make lint       ✅  0 warnings
make fmt-check  ✅  no diff
make test       ✅  12 tests, 0 failures
make doctor     ✅  all checks passed (offline)
```

## Dry-run Output

<!-- Paste tail of: CI=true bash codex.sh basic --dry-run --skip-docker --skip-optional -->

```
[Codex] Running Basic Installation...
[DRY RUN] Would install: node@20.x
[DRY RUN] Would write: ~/.codex/config.toml
[Codex] Process finished successfully.
```

## Security Impact

<!-- State: "No security impact" OR describe the threat surface change. -->
<!-- Required for any change touching scripts/lib/security.sh, safe_download, -->
<!-- safe_extract_tar, checksum verification, or Codex config generation.     -->

## Breaking Changes

<!-- "None" OR describe what breaks and the migration path. -->
<!-- If breaking: add BREAKING CHANGE footer to the squash commit message.    -->

## Platform Coverage

<!-- Confirm which platforms this was validated on, or which are affected. -->

- [ ] Ubuntu 22.04 amd64
- [ ] Ubuntu 22.04 arm64
- [ ] Ubuntu 24.04 amd64
- [ ] Ubuntu 24.04 arm64

## Checklist

- [ ] `make lint` passes (ShellCheck + bash -n)
- [ ] `make fmt-check` passes (shfmt)
- [ ] `make test` passes (Bats)
- [ ] `make doctor` passes (offline)
- [ ] `make validate` passes
- [ ] No hardcoded secrets, tokens, or passwords in any file
- [ ] No `curl | bash` or hidden execution patterns added
- [ ] `CHANGELOG.md` updated under `## [Unreleased]` (if user-visible)
- [ ] Relevant `docs/` files updated (if behaviour or architecture changed)
- [ ] Dry-run output included above
- [ ] New code paths covered by Bats tests
- [ ] Installer dry-run tested: `CI=true bash codex.sh basic --dry-run --skip-docker`
```

---

## 5. CHANGELOG ENTRY FORMAT

Every user-visible PR must add an entry under `## [Unreleased]` in `CHANGELOG.md`:

```markdown
## [Unreleased]

### Added
- Installer: `--skip-optional` now also skips `shfmt` installation on minimal hosts.

### Fixed
- `safe_extract_tar`: reject archives containing `../` or absolute paths before extraction.

### Security
- `safe_download`: enforce `Content-Type: application/octet-stream` guard.

### Changed
- Doctor `--repair` now backs up existing Codex config before rewriting.

### Removed
- `--skip-verify` flag removed; SHA-256 verification is now unconditional.
```

Use the correct sub-heading: `Added`, `Fixed`, `Security`, `Changed`, `Removed`, `Deprecated`.
Entries are concise — one line per change, written for an operator reading the release notes.

---

## 6. SCOPE-SPECIFIC PR RULES

### 6.1 Security changes (`scripts/lib/security.sh`, `safe_download`, checksums)

Additional requirements:
- PR description **must** include a "Threat Mitigated" paragraph.
- Negative Bats test (the attack path must fail) is required.
- Tag the PR with the `security` label.
- Do not squash into a larger feature PR. Security fixes are standalone.

### 6.2 Installer phase changes (`scripts/install-codex-ubuntu.sh`)

Additional requirements:
- Dry-run output for **all four platform combos** (22.04+24.04 × amd64+arm64) or
  explain why they were not tested.
- Rollback path must be described: what happens if this phase fails mid-run.
- Phase state transition diagram update in `docs/manifest-state.md` if a new
  phase is added.

### 6.3 CI workflow changes (`.github/workflows/`)

Additional requirements:
- All third-party actions must be pinned to a SHA (not a tag):
  `uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683`
- Justify any new permissions granted in the workflow YAML.
- Do not add `secrets: inherit` without explicit justification.

### 6.4 Release PRs (`release/vX.Y.Z`)

Additional requirements:
- `VERSION` file contains only the new version string, no trailing newline issues.
- `CHANGELOG.md` has a `## [vX.Y.Z] — YYYY-MM-DD` section with all entries moved
  from `## [Unreleased]`.
- `make release && make release-checksum` output is pasted in the PR description.
- The PR targets `main` and is the **only open PR** at merge time.
- Squash commit message: `release: vX.Y.Z`.

### 6.5 Documentation-only PRs (`docs/`)

- Still require `make lint` (shellcheck catches code in docs snippets).
- No test changes needed.
- Title must use `docs(<scope>):` type.

---

## 7. REVIEW RESPONSE RULES (for Codex agents addressing feedback)

- Address every review comment with either a code change or an explicit
  explanation of why the change was not made.
- Re-run `make validate` after every fixup commit.
- Use `git commit --fixup=HEAD` for small corrections, then `git rebase -i`
  to squash before final approval.
- Never push `--force` to `main`. Only force-push to your own feature branch
  and only before review has started.
- After addressing all comments, post a brief summary:
  ```
  All review comments addressed. make validate passes. Ready for final review.
  ```

---

## 8. WHAT CODEX AGENTS MUST NEVER DO IN A PR

- Open a PR from `main` to `main`.
- Include generated `dist/` tarballs, `*.log` files, or `sbom.*.json`.
- Include `node_modules/`, `__pycache__/`, or other build artifacts.
- Merge their own PR (self-merge is blocked by branch protection).
- Mark a PR "ready for review" while any CI check is failing.
- Use `[skip ci]` in commit messages to bypass the gate.
- Add a dependency that requires a non-MIT-compatible license.
- Remove or weaken the reproducibility gate in `release-validate.yml`.

---

## 9. PR SIZE GUIDANCE

| Lines changed | Guidance |
|---|---|
| 1–50 | Fine as a standalone PR |
| 51–200 | Normal. Must have clear scope. |
| 201–500 | Add a "Why this is one PR" paragraph to the description. |
| 500+ | Split into multiple PRs unless it is a mechanical rename/reformat. |

Codex agents should prefer smaller, focused PRs. A well-scoped 80-line PR
ships faster and is easier to review safely than a 600-line "omnibus" PR.

---

## 10. LABELS (apply to every PR)

| Label | When |
|---|---|
| `security` | Any change to security primitives |
| `breaking` | Removes or renames a public flag or API |
| `documentation` | Docs-only PR |
| `ci` | CI workflow changes only |
| `release` | Release prep PR |
| `needs-review` | PR is ready for human review |
| `in-progress` | Draft — not ready for review |

---

*Last updated: 2026-05-10 — zcodex Codex-Max v1.0*
