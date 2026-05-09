# Security Policy

`zcodex` is an installer and runtime bootstrapper, so security reports are taken seriously even when the affected code is shell-only.

## Supported versions

Security fixes target the latest release and the `main` branch. Older versions may receive fixes when the impact is high and the patch is low risk.

| Version | Supported |
| --- | --- |
| `main` | Yes |
| latest tagged release | Yes |
| older releases | Best effort |

## Reporting a vulnerability

Please report suspected vulnerabilities privately through GitHub Security Advisories for `cvsz/zcodex` when available. If GitHub private reporting is unavailable, contact the maintainer through the repository owner's public GitHub profile and avoid including exploit details in public issues.

Include:

- Affected version, commit, or tag.
- Host OS and architecture.
- Reproduction steps or proof of concept.
- Impact assessment.
- Whether the issue affects default installs, optional Docker setup, release artifacts, or local configuration.

## Response expectations

The maintainer will aim to:

1. Acknowledge valid reports within 7 days.
2. Confirm impact and affected versions.
3. Prepare a minimal fix and regression test when practical.
4. Publish a patched release and changelog entry for confirmed vulnerabilities.
5. Credit reporters unless they request otherwise.

## Security design scope

Security-sensitive project areas include:

- Download and checksum verification helpers.
- Installer temporary directories and cleanup.
- File permissions for manifests, state, config, and backups.
- Release artifact generation and checksum publication.
- Shell profile modification and rollback behavior.
- Optional Docker installation paths.

## Out of scope

The project does not provide a sandbox for arbitrary model-generated commands, does not store API keys, and does not replace host hardening. Users remain responsible for reviewing commands before running installer scripts on production systems.

## Hardening architecture references

- See [THREAT_MODEL.md](THREAT_MODEL.md) for assets, trust boundaries, and attack-surface mitigations.
- See [SECURITY_ARCHITECTURE.md](SECURITY_ARCHITECTURE.md) for PATH, privilege, runtime ownership, manifest, and release security architecture.

## Deterministic CI and E2E security validation

Security validation is part of the primary CI workflow and the containerized E2E workflow. The test harness isolates HOME, TMPDIR, XDG directories, and PATH. Runtime behavior that depends on Node.js, npm, Codex, or `dpkg-query` should be represented as a fixture under `tests/runtime-fixtures/` rather than by relying on software preinstalled on a CI runner.

## Runtime trust semantics

- npm is trusted only when `node` and `npm` resolve to the same verified ownership
  domain: distro APT, NodeSource APT, nvm, or asdf. Unknown or unowned binaries
  block mutation in `clean-system` mode.
- Global npm installs into nvm/asdf runtimes require
  `ZCODEX_ALLOW_USER_RUNTIME_MUTATION=true`; this is an explicit operator
  assertion that mutating the active user runtime is intended.
- Privileged commands run with a fixed secure PATH. `sudo` must resolve from a
  trusted system directory, and PATH entries that are writable by untrusted
  principals are rejected before privileged work.
- zcodex assumes `sudo` policy is already configured by the host administrator;
  it does not attempt to bypass, weaken, or configure sudoers policy.


## Secure development workflow guardrails

- Pre-commit hooks are configured in `.pre-commit-config.yaml` to block basic secret leakage patterns and enforce shell hygiene before commits.
- Workflow policy tests enforce explicit least-privilege GitHub Actions permissions and block risky triggers/scopes.
- Branch protection requirements are documented in `.github/branch-protection-ruleset.md` and should be enforced for `main`.
