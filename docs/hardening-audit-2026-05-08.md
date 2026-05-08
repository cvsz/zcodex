# Full Repository Hardening Audit — 2026-05-08

## Executive summary

zcodex already had a strong modular Bash foundation: deterministic pins,
state-driven install phases, runtime ownership checks, release artifacts, CI,
and Bats coverage. The main maturity gaps were around strict PATH handling,
privileged command boundaries, manifest schema validation, append-only install
records, explicit production runtime policy, and release reproducibility proof.

## Architecture review

The repository remains intentionally Bash-first. Entry points delegate to
`scripts/lib` modules, and the installer continues to use explicit phases rather
than a generic framework. The patch strengthens boundaries without introducing a
plugin system or package-manager clone.

## Security review

Key risks identified:

- PATH shadowing before privileged execution.
- Sudo resolution through user-controlled PATH.
- Manifest publication without schema validation.
- Runtime mutation ambiguity for production hosts.
- Reproducibility not verified during release generation.

Mitigations implemented in this patch address those risks directly.

## Operational risk review

Recovery remains phase-marker based. Atomic state writes and validated manifests
reduce corruption risk after interruption. Rollback is still scoped to managed
user files and intentionally does not attempt to reverse arbitrary apt
transactions.

## Maintainability review

The patch avoids broad refactors. New functionality is isolated in existing
security, exec, state, manifest, release, and runtime modules. Tests document the
new invariants.

## Shell engineering review

The patch avoids `eval`, keeps command arguments array-safe, and keeps traps
centralized. Privileged commands now use a single wrapper rather than repeated
raw `sudo` calls.

## Proposed architecture changes

1. Treat PATH validation as an installer gate.
2. Treat `runtime_privileged` as the shared privilege boundary.
3. Treat manifest schema version 2 as the current durable install contract.
4. Treat release reproducibility as a required release gate.
5. Treat production as an explicit existing-runtime policy.

## Migration steps

- Existing manifests with schema version 1 remain historical records.
- The next successful installer run writes schema version 2 and appends an
  install record.
- Production automation should pass `--runtime-mode production` after baking the
  pinned Node.js/npm runtime into the image.
- CI should continue using `make validate` and release tags must match `VERSION`.

## Risk mitigations

- If strict PATH validation fails, fix shell profile PATH entries rather than
  bypassing validation.
- Use `ZCODEX_ALLOW_INSECURE_PATH=true` only for diagnosis.
- Use `ZCODEX_ALLOW_USER_RUNTIME_MUTATION=true` only after reviewing npm global
  mutation impact.

## Rollback strategy

- Restore managed user-file backups from the zcodex backup directory.
- Re-run the installer after correcting PATH or runtime ownership conflicts.
- Remove a failed `dist/` release output and rerun `scripts/release.sh`.

## Implementation roadmap

- Add signed `SHA256SUMS` after signing ownership is finalized.
- Add SBOM generation once the release pipeline chooses a supported SBOM tool.
- Expand runtime detection for additional package managers only when operational
  demand appears.
