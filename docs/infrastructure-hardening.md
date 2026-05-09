# Infrastructure hardening review

This review documents the production hardening model for zcodex as a deterministic infrastructure bootstrap runtime.

## Root-cause analysis

The historical instability risks were not isolated defects; they came from repeated reliance on ambient host state:

1. **Process environment drift**: locale, timezone, umask, HOME, TMPDIR, and XDG paths could vary between developer shells, GitHub-hosted runners, containers, and release jobs.
2. **Runtime discovery drift**: Node.js, npm, Docker, Codex, and `dpkg-query` detection could accidentally observe host-provided binaries instead of intentional fixtures or policy-controlled runtime paths.
3. **Archive nondeterminism**: filesystem traversal order, tar metadata, gzip headers, timestamps, and ownership metadata must be normalized for reproducible release bytes.
4. **Test pollution**: tests need isolated HOME, TMPDIR, XDG directories, runtime fixture PATHs, and explicit cleanup to avoid inheriting runner-level tools or user configuration.
5. **Workflow fragmentation**: duplicated shellcheck/format workflows made CI behavior easier to drift from release validation and E2E validation.
6. **Observability gaps**: failures need deterministic snapshots and bundles that can be uploaded by CI without exposing mutable host paths as operational truth.

## Architecture review

The hardened architecture keeps Bash as the orchestration language while separating concerns into small modules:

- `scripts/lib/environment.sh` normalizes locale, timezone, umask, deterministic sorting helpers, stable jq invocation, and timestamp helpers.
- `scripts/lib/context.sh` remains the explicit runtime context store for phase and policy metadata.
- `scripts/lib/state.sh` owns installer state transitions and interrupted phase recovery.
- `scripts/lib/manifest.sh` owns schema validation, deterministic serialization order, component inventory, package inventory, runtime hashes, and install records.
- `scripts/lib/security.sh` owns PATH validation, privileged command boundaries, lockfiles, secure temp directories, downloads, and checksum verification.
- `tests/helpers/runtime.bash` owns Bats isolation and runtime fixture injection.
- `scripts/e2e-runner.sh` owns host-independent containerized scenario execution.
- `scripts/diagnostics.sh` owns deterministic failure bundles.

## Deterministic systems review

Determinism is enforced at multiple layers:

- `LC_ALL=C.UTF-8`, `LANG=C.UTF-8`, and `TZ=UTC` are exported by the runtime environment layer.
- Sorting uses `LC_ALL=C sort` through helper wrappers.
- JSON diagnostics are emitted with stable key order in generated documents.
- Release archives use sorted tar entries, normalized owners, normalized groups, numeric owners, normalized timestamps, POSIX tar metadata, and `gzip -n`.
- Diagnostic bundles use the same tar/gzip normalization pattern and support `SOURCE_DATE_EPOCH`.
- E2E scenarios are sorted before execution so matrix output is stable.

## CI hardening review

CI is split into four primary workflows:

1. `ci.yml`: lint, shellcheck, shfmt, Bats, workflow policy, E2E plan validation, release reproducibility, and security audit jobs.
2. `release-validate.yml`: release tag/version/changelog/orchestrator dry-run validation.
3. `release.yml`: tag-only artifact generation, reproducibility gate, checksum verification, artifact upload, and GitHub Release publication.
4. `e2e.yml`: containerized Ubuntu/architecture scenario validation.

Each workflow exports deterministic locale/timezone variables and creates isolated HOME/TMPDIR/XDG workspaces before invoking project code.

## Security review

Security controls focus on fail-safe runtime ownership and command resolution:

- PATH entries are rejected when empty, relative, unreadable, duplicate after canonicalization, or writable by an untrusted principal.
- Privileged execution uses a constrained secure PATH and refuses shadow `sudo` binaries outside trusted system locations.
- Downloads are HTTPS-only and can be pinned to SHA-256 checksums.
- Checksum manifests reject malformed digests and missing artifact entries.
- Locking prevents concurrent installer mutation of shared state.
- Secure temporary directories are mode `0700` and cleaned only when they match expected zcodex temp path shapes.
- Runtime fixtures model malicious injection, broken npm, stale runtime, corrupted manifests, and PATH shadowing without mutating the host.

## Release engineering review

Release generation is deterministic and auditable:

- Archives are built from a Git tree rather than a mutable working directory.
- Archive byte streams are rebuilt in-process and compared before release completion.
- `SHA256SUMS` is generated in the artifact directory.
- Release notes are extracted from `CHANGELOG.md` for the selected version.
- Signing and SBOM instructions are generated with stable file names so future signing can be added without changing artifact contracts.

## E2E strategy

The E2E runner supports Ubuntu 22.04, Ubuntu 24.04, amd64, and arm64. The scenario table covers fresh install, interrupted recovery, repair mode, rollback behavior, runtime conflicts, manifest reconciliation, deterministic release generation, strict policy mode, developer policy mode, and CI policy mode. Docker execution mounts the repository read-only and creates isolated HOME/TMPDIR/XDG directories inside each container.

## Repository restructuring plan

The hardening split is intentionally minimal:

- Keep reusable runtime logic in `scripts/lib/`.
- Keep test isolation in `tests/helpers/`.
- Keep host-independent runtime simulations in `tests/runtime-fixtures/`.
- Keep scenario definitions in `tests/e2e/`.
- Keep operational diagnostics in `scripts/diagnostics.sh`.
- Keep workflow responsibilities in `ci.yml`, `release-validate.yml`, `release.yml`, and `e2e.yml`.

## Migration plan

1. Continue supporting existing installer flags and runtime modes.
2. Prefer `tests/helpers/runtime.bash` for new tests instead of local ad hoc `mktemp` and PATH setup.
3. Add future runtime scenarios as new directories under `tests/runtime-fixtures/` and new rows in `tests/e2e/scenarios.tsv`.
4. Treat release artifacts as reproducibility-gated outputs; do not publish artifacts that fail byte-for-byte rebuild checks.
5. Add SBOM and signing outputs after ownership for keys/OIDC policy is established.

## Reproducibility guarantees

The hardened system guarantees stable behavior for the same Git tree, version, release ref, environment variables, and fixture set. Release archive bytes are reproducible across repeated builds, diagnostics can be reproduced with `SOURCE_DATE_EPOCH`, and tests execute with isolated HOME/TMPDIR/XDG/PATH state.

## Operational guarantees

The runtime now provides explicit phase state, recoverable interrupted installs, deterministic manifests, security-aware PATH handling, fixture-based runtime simulations, containerized E2E validation, release checksums, and CI-uploadable diagnostic bundles.
