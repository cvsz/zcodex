# Root cause analysis

Date: 2026-05-09

## RC-1: Ambient process environment leaked into shell behavior

- Cause: Several entry points relied on the caller's `LC_ALL`, `LANG`, and `TZ` until a runtime library was sourced, or never normalized the environment at all.
- Impact: Locale-aware utilities could produce different ordering, class matching, and timestamps across developer machines and CI images.
- Fix: Export `LC_ALL=C.UTF-8`, `LANG=C.UTF-8`, and `TZ=UTC` near process start in standalone entry points.
- Prevention: Keep environment normalization in new entry points before parsing input or invoking text utilities.

## RC-2: Release archive timestamp followed Git metadata

- Cause: The release archive normalized tar metadata, but mtime was derived from `SOURCE_DATE_EPOCH` or the commit timestamp.
- Impact: Rebuilding equivalent source trees from different refs or commit metadata could produce different archive hashes.
- Fix: Use fixed release mtime `UTC 2025-01-01` in the deterministic tar invocation.
- Prevention: Treat release artifact metadata as part of the compatibility contract.

## RC-3: File traversal order depended on locale in one validation path

- Cause: The Makefile lint file list used `sort -z` without an explicit C locale.
- Impact: ShellCheck input order could differ by locale, creating noisy CI/local differences and masking traversal assumptions.
- Fix: Use `LC_ALL=C sort -z` for the lint file list.
- Prevention: Any `find ... -type f` pipeline must sort with `LC_ALL=C` before consumption.

## RC-4: Workflow images remain a drift source

- Cause: Workflows install tool packages from the current runner/apt image rather than pinned container digests.
- Impact: ShellCheck, shfmt, bats, tar, gzip, and Python versions can drift over time.
- Fix: Not changed because workflows were explicitly out of scope.
- Prevention: Future workflow hardening should pin tool versions or execute validation in a repository-owned image.

## RC-5: Runtime state is intentionally host-specific

- Cause: Manifest and state files include runtime versions, PATH digest, command hashes, and install timestamps.
- Impact: Runtime manifests are deterministic for a fixed host/runtime input, but not portable release artifacts.
- Fix: No code change; release artifacts are built only from the committed Git tree.
- Prevention: Keep runtime diagnostics separate from release reproducibility claims.
