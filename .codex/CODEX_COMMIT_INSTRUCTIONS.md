# CODEX_COMMIT_INSTRUCTIONS.md
# Repository: https://github.com/cvsz/zcodex
# Scope: Rules for every git commit created by a Codex agent in this repo.
# ================================================================
#
# Read this file before writing any commit. These rules are binding.
# Non-conforming commits will fail the CI commit-lint gate.
#
# ================================================================

## 1. COMMIT MESSAGE FORMAT (Conventional Commits — enforced)

```
<type>(<scope>): <subject>

[body — required for non-trivial changes]

[footer]
```

Every part must conform to the rules below.

---

## 2. SUBJECT LINE RULES

- **Format**: `<type>(<scope>): <subject>`
- **Length**: ≤ 72 characters total (hard limit).
- **Case**: lowercase type and scope; subject starts lowercase, no period at end.
- **Tense**: imperative present ("add", "fix", "remove") — never past tense.
- **No filler**: avoid "update", "change", "misc", "various", "wip".

### Valid examples
```
feat(installer): add arm64 detection to platform capability probe
fix(security): prevent path traversal in safe_extract_tar
docs(architecture): clarify state transition diagram for VERIFY phase
chore(ci): pin shellcheck action to v2.2.4 with SHA256
test(doctor): add offline repair regression for missing manifest
refactor(lib): split installer.sh download helpers into security.sh
security(lib): enforce HTTPS-only in safe_download curl flags
```

### Invalid examples
```
Updated the installer                  ← no type, past tense
fix: fixed stuff                       ← vague subject, past tense
feat(installer): Add ARM64 Detection.  ← wrong case + period
WIP: changes                           ← never commit WIP to main
```

---

## 3. TYPE DEFINITIONS

| Type | When to use |
|---|---|
| `feat` | New user-visible behaviour or installer capability |
| `fix` | Corrects a bug or broken behaviour |
| `security` | Hardens a security primitive or closes a vulnerability |
| `docs` | Documentation-only change (no script changes) |
| `test` | Adds or fixes Bats tests; no production code change |
| `chore` | Tooling, CI workflow, Makefile, `.editorconfig`, `.gitignore` |
| `refactor` | Code restructuring with no behaviour change |
| `ci` | Changes to `.github/workflows/` only |
| `release` | VERSION bump, CHANGELOG entry, tag preparation |
| `revert` | Reverts a previous commit — reference it in the footer |

> **Do not invent new types.** If in doubt, use `chore`.

---

## 4. SCOPE DEFINITIONS

| Scope | Maps to |
|---|---|
| `installer` | `scripts/install-codex-ubuntu.sh` |
| `orchestrator` | `codex.sh` |
| `doctor` | `scripts/doctor.sh` |
| `validator` | `scripts/validate-environment.sh` |
| `e2e` | `scripts/e2e-runner.sh` |
| `lib` | Any file under `scripts/lib/` |
| `security` | `scripts/lib/security.sh` specifically |
| `runtime` | `scripts/lib/runtime.sh` specifically |
| `platform` | `scripts/lib/platform.sh` specifically |
| `tests` | Files under `tests/` |
| `ci` | Files under `.github/workflows/` |
| `config` | `config/zcodex/config.toml` or Codex config |
| `docs` | Files under `docs/` |
| `release` | `VERSION`, `CHANGELOG.md`, `Makefile` release targets |
| `makefile` | `Makefile` changes unrelated to release |

> Multiple scopes allowed when genuinely needed: `fix(lib,tests):`.
> Omit scope only for repo-wide or cross-cutting changes.

---

## 5. COMMIT BODY RULES

Required when:
- The change touches `scripts/lib/security.sh` or any security primitive.
- A new installer phase is added or an existing one is modified.
- A CI workflow is changed.
- A dependency version is pinned or updated.
- The fix is non-obvious without context.

Body format:
- Blank line between subject and body.
- Wrap at 80 characters.
- Explain the **why** and the **risk**, not just the what.
- For security changes, state the threat that is mitigated.
- For bug fixes, describe the failure mode that was observed.

```
fix(security): enforce Content-Type guard in safe_download

Without the Content-Type check, a compromised CDN could serve an
HTML error page that passes the SHA-256 step if the expected hash
happens to match. The guard now rejects any response whose
Content-Type does not start with application/octet-stream or
application/x-tar.

Risk before: silent installation of attacker-controlled content.
Risk after: hard abort with non-zero exit and error log entry.
```

---

## 6. FOOTER RULES

Use footers for:
- Issue references: `Closes #42`, `Fixes #17`, `Refs #99`
- Breaking changes: `BREAKING CHANGE: <description>`
- Co-authors: `Co-authored-by: Name <email>`
- Reverts: `Reverts: <full subject of reverted commit>`

Breaking change format:
```
BREAKING CHANGE: --skip-verify flag removed from install-codex-ubuntu.sh.
All downloads are now SHA-256 verified unconditionally.
Callers relying on --skip-verify must update their invocations.
```

---

## 7. ATOMIC COMMIT RULES

Each commit must represent exactly one logical change:

- **One fix per commit.** Do not bundle two unrelated bug fixes.
- **Tests travel with the code.** If you add a function, add its Bats test
  in the same commit — not a separate "add tests" commit.
- **Docs travel with the behaviour.** If you change a flag name,
  update its docs entry in the same commit.
- **Formatting is separate.** A shfmt reformat must be its own commit:
  `chore(lib): reformat installer.sh with shfmt`
- **Version bumps are separate.** Never mix a feature commit with a
  `VERSION` file change.

---

## 8. SECRET HYGIENE — PRE-COMMIT CHECKLIST

Before every `git commit`, verify:

```bash
# No raw tokens in staged diff
git diff --cached | grep -Ei 'ghp_|ghs_|sk-[a-z0-9]{48}|GITHUB_TOKEN\s*=\s*[^\$]|OPENAI_API_KEY\s*=\s*[^\$]'

# No log files staged
git diff --cached --name-only | grep -E '\.(log|tmp)$'

# Shell syntax OK for every staged .sh file
git diff --cached --name-only | grep '\.sh$' | xargs -r bash -n

# ShellCheck passes
git diff --cached --name-only | grep '\.sh$' | xargs -r shellcheck --shell=bash
```

If any check fails → `git reset HEAD <file>` and fix before committing.

---

## 9. COMMIT SIGNING (optional but encouraged)

If GPG is configured:
```bash
git config commit.gpgsign true
git commit -S -m "feat(installer): ..."
```

CI `release-validate.yml` checks for signed commits on release branches.

---

## 10. WHAT CODEX AGENTS MUST NEVER COMMIT

- Files matching: `*.log`, `*.tmp`, `codex_release.log`, `sbom.*.json`
- Files under: `${HOME}/.zcodex/`, `${HOME}/.local/share/zcodex/`
- Any file containing a raw `GITHUB_TOKEN`, `OPENAI_API_KEY`, or private key
- Generated `dist/` tarballs (the release workflow builds these from the tag)
- `node_modules/`, `__pycache__/`, `.DS_Store`
- Binary files not explicitly tracked in the repo already

---

## 11. AMEND & REBASE POLICY

- `git commit --amend` is allowed on your **own** branch before PR review.
- Interactive rebase (`git rebase -i`) is allowed to squash fixup commits.
- **Never force-push to `main` or a release branch.**
- Squash merge into `main` is the default strategy — keep your branch
  commits clean so the squash message is meaningful.

---

*Last updated: 2026-05-10 — zcodex Codex-Max v1.0*
