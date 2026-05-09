# Repository audit

Date: 2026-05-09

## Scope

- Audited `scripts/`, `tests/`, `.github/workflows/`, release scripts, manifest/state logic, runtime ownership checks, PATH validation, lock/temp handling, and recovery semantics.
- Constraints honored: README and workflows were not modified; no E2E implementation was added.

## Phase 1 findings

| Area | Evidence | Risk | Status |
| --- | --- | --- | --- |
| Process locale | Some standalone entry points did not export locale/timezone before parsing or calling utilities. | Locale-sensitive `sort`, `tr`, `grep`, `awk`, and timestamp formatting can drift by host. | Fixed in Phase 2. |
| Release mtime | Release archive mtime previously derived from Git commit time unless overridden. | Same file tree can hash differently across equivalent refs with different commit timestamps. | Fixed to `UTC 2025-01-01`. |
| ShellCheck file traversal | Makefile lint target sorted with ambient locale. | CI/local file order can differ under non-C locales. | Fixed with `LC_ALL=C sort -z`. |
| Release archive ordering | Release path already used `tar --sort=name`, normalized owner/group, and `gzip -n`. | Low; deterministic foundation exists. | Retained and documented. |
| Diagnostics archive | Diagnostics bundle records current host facts and current epoch. | Intended runtime snapshot, not release artifact; not byte-reproducible by design. | Documented as non-release output. |
| Manifest writes | Manifest write uses temp file plus `mv`; schema validation exists. | Good crash behavior for main manifest; JSONL install records remain append-only mutable history. | Acceptable, documented. |
| State history | Current phase/status files are atomic; history is append-only. | Concurrent writers could interleave without the installer lock. | Installer lock remains required. |
| PATH validation | Security library canonicalizes PATH and rejects writable/suspicious segments unless explicitly bypassed. | Good boundary; bypass env var can leak risk into manual runs. | Documented. |
| Runtime ownership | Runtime audit distinguishes managed/unmanaged Node/npm/codex and production policy. | Good; package manager detection remains intentionally limited to repository-supported sources. | No change. |
| Tempdirs | Installer tempdirs use `mktemp -d` and cleanup guard. | Good; cleanup guard is conservative. | No change. |
| Workflows | CI/release workflows pin broad Ubuntu runner labels and install apt tooling at runtime. | GitHub runner image drift remains possible. | Not modified per constraint. |

## Hidden bugs and shell safety notes

- `codex.sh`, `validate-release.sh`, `validate-release-tag.sh`, `validate-environment.sh`, `maintenance-setup.sh`, and `uninstall-codex.sh` had no early locale/timezone normalization before local path/log/version handling.
- `scripts/release.sh` verified repeatability within one invocation, but its timestamp source allowed runtime drift by ref metadata.
- No unsafe `eval` pattern was found in audited shell code.
- Privileged execution is centralized via `runtime_privileged`, reducing duplicated `sudo` behavior.
- Raw command discovery remains present where appropriate, but privileged `sudo` resolution is checked against trusted paths.

## Validation gates

- ShellCheck must cover `codex.sh`, `scripts/**/*.sh`, and `tests/**/*.bash` in deterministic path order.
- shfmt must pass for `codex.sh`, `scripts`, `tests`, and the added reproducibility validation script.
- Release validation must produce identical archives and matching `SHA256SUMS` across two clean output directories.
