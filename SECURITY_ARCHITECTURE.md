# Security Architecture

## Design principles

- Deterministic execution over implicit shell behavior.
- Fail-safe runtime ownership policy for Node.js/npm.
- Minimal privileged surface: only package-manager and system-global npm commands
  cross the privilege boundary.
- Machine-readable state and manifests with recovery-safe writes.

## Privilege boundary

`runtime_privileged` is the only shared wrapper for privileged commands. It:

1. uses root directly only when the caller is already root;
2. requires `sudo` for non-root execution;
3. accepts only `/usr/bin/sudo` or `/bin/sudo`; and
4. executes privileged commands with a fixed secure PATH.

## PATH policy

Before installer work, zcodex validates PATH for:

- non-empty value;
- no empty segments;
- absolute entries only;
- existing canonical directories; and
- no group/other writable or user-owned untrusted entries for privileged use.

Operators can set `ZCODEX_ALLOW_INSECURE_PATH=true` only to diagnose unusual
legacy environments. Production automation should never set this variable.

## Runtime ownership policy

Supported modes are:

- `clean-system`: zcodex may install managed distro packages but refuses
  user-managed Node.js/npm.
- `existing-runtime`: zcodex uses an operator-provided compatible runtime and
  does not install Node.js/npm.
- `developer`: equivalent to existing runtime with developer-oriented guidance.
- `ci`: requires the image to include the pinned runtime.
- `production`: requires an existing compatible runtime and keeps package
  mutation explicit.

## Manifest architecture

Manifest schema version 2 records:

- installer and environment mode;
- platform and capability metadata;
- state phase/status/install id;
- runtime ownership audit output;
- component versions and binary hashes; and
- verification input hashes.

Each published manifest is validated before rename and then recorded in an
append-only `install-records.jsonl` file with the manifest SHA-256 digest.

## Release architecture

Release artifacts are generated from a committed git tree with `git archive` and
`gzip -n`. The release script builds the archive twice and compares SHA-256
hashes before publishing `SHA256SUMS`. Signing and SBOM hooks are intentionally
prepared but not enabled until repository key ownership is finalized.

## Deterministic runtime hardening layer

The runtime now normalizes `LC_ALL=C.UTF-8`, `LANG=C.UTF-8`, and `TZ=UTC` through `scripts/lib/environment.sh` before installer libraries are loaded. Security-sensitive tests inject explicit runtime fixtures from `tests/runtime-fixtures/` instead of relying on host Node.js, npm, Docker, Codex, or `dpkg-query` state. CI and E2E workflows create isolated HOME, TMPDIR, and XDG directories before invoking repository code.

Failure investigation should use `scripts/diagnostics.sh`, which writes a deterministic JSON runtime snapshot and normalized tar/gzip failure bundle suitable for CI artifact upload.

## 2026 hardening additions

- PATH shadowing checks expose `security_detect_path_shadowing` for privileged
  command boundaries such as `sudo`, `apt-get`, `node`, and `npm`.
- Temporary directory creation validates that world-writable parents have sticky
  semantics before creating private `0700` work directories.
- Manifest v2 files are deterministically serialized and sealed with a canonical
  SHA-256 integrity digest.
- State reconciliation validates persisted phases/statuses and removes stale
  completion markers instead of trusting interrupted install state blindly.
- Release builds run a checksum verification gate immediately after writing
  `SHA256SUMS`.
