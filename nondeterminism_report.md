# Nondeterminism report

Date: 2026-05-09

## Eliminated in this patch

| Pattern | Location | Replacement |
| --- | --- | --- |
| Ambient locale/timezone | Standalone Bash entry points | Early `LC_ALL=C.UTF-8`, `LANG=C.UTF-8`, `TZ=UTC` exports |
| Locale-sensitive lint traversal | `Makefile` lint target | `find ... -print0 | LC_ALL=C sort -z` |
| Git timestamp release mtime | `scripts/release.sh` | Fixed `tar --mtime='UTC 2025-01-01'` |
| Manual two-build verification gap | Repository root | Added `reproducibility_validation.sh` |

## Confirmed deterministic release controls

- Archive source: committed Git tree via `git archive` into a staging directory.
- File ordering: `tar --sort=name`.
- Metadata: fixed mtime, owner `0`, group `0`, and numeric ownership.
- Compression: `gzip -n`.
- Checksums: `sha256sum` over the deterministic archive name.
- Rebuild validation: two clean builds plus `sha256sum -c` and `cmp`.

## Remaining accepted nondeterminism

| Area | Reason |
| --- | --- |
| Runtime manifests | They intentionally describe the current host runtime, PATH digest, command versions, and command hashes. |
| Diagnostics bundle | It is a point-in-time troubleshooting snapshot, not a release artifact. |
| GitHub runner package versions | Workflows were not modified in this phase by request. |
| Network/package manager state | Installer resolves apt/npm state at runtime; dry-run and validation reduce but cannot remove host package drift. |

## Repository rule

Use deterministic traversal and serialization in new shell code:

```bash
find . -type f | LC_ALL=C sort
jq -S '.'
tar --sort=name --mtime='UTC 2025-01-01' --owner=0 --group=0 --numeric-owner -cf - INPUT | gzip -n
```
