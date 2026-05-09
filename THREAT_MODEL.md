# zcodex Threat Model

## Scope

zcodex is a Bash-first bootstrap runtime for Ubuntu hosts. Its trusted computing
base is the checked-out repository, the system package manager, trusted release
artifacts, and the host administrator who invokes the installer.

## Primary assets

- Host package-manager state and privileged package operations.
- Node.js/npm runtime ownership and global npm installation target.
- Codex CLI configuration in the invoking user's home directory.
- Install state, manifest, and immutable install-record log under
  `${HOME}/.local/share/zcodex`.
- Release archives and SHA-256 checksum manifests.

## Trust boundaries

1. **User shell to privileged operations**: untrusted PATH entries must not affect
   sudo-mediated `apt-get` or npm operations.
2. **Network to local artifacts**: downloads must use HTTPS and be verified by
   SHA-256 when a digest or checksum manifest is available.
3. **Existing runtime to managed runtime**: nvm/asdf/user-owned runtimes are not
   mutated unless an explicit operator opt-in is set.
4. **Interrupted install to resumed install**: persisted state is advisory, but
   completed phase markers and manifest writes are recovery-safe and validated.
5. **Release source to artifact**: release tarballs are built from a git tree,
   compressed deterministically, checksummed, and rebuilt once to prove
   reproducibility.

## Threats and mitigations

| Threat | Mitigation |
| --- | --- |
| PATH shadowing of `sudo`, `apt-get`, `npm`, or `node` | strict PATH validation, canonicalization, trusted sudo path enforcement, and secure PATH for privileged execution |
| Global npm install into a user runtime | runtime ownership classification and `ZCODEX_ALLOW_USER_RUNTIME_MUTATION` fail-safe default |
| Manifest corruption or partial writes | temp-file write, schema validation before publish, mode 600 files, append-only install-record log |
| Concurrent installers | flock-backed process lock with explicit lock path |
| Insecure temporary workspace cleanup | mode 700 `zcodex.*` workspace and guarded cleanup prefix checks |
| Artifact tampering | HTTPS-only downloads, SHA-256 validation, release `SHA256SUMS`, and signing hooks |
| Package-manager confusion between distro Node.js and NodeSource | package-origin classification and conflict guidance |

## Non-goals

- zcodex does not replace apt, npm, nvm, or asdf.
- zcodex does not promise rollback for arbitrary system packages installed by apt.
- zcodex does not install unsigned third-party package repositories by default.

## Fixture-mode adversarial scenarios

The test fixture system models adversarial or unsafe local runtime conditions without mutating the host:

- `broken-npm` simulates a corrupt npm prefix.
- `corrupted-manifest` simulates malformed manifest input.
- `interrupted-install` simulates resumable phase state.
- `stale-runtime` simulates an obsolete Codex binary and stale manifest.
- `path-shadowing` simulates a malicious binary ahead of trusted system paths.

These scenarios defend against environment contamination, PATH shadowing, runtime ownership confusion, and manifest/state recovery regressions.
