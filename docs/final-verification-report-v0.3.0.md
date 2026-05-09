# Final Verification Report: v0.3.0

Date: 2026-05-09
Version: `0.3.0`
Release tag: `v0.3.0`

## Scope

This report records the final production-release preparation for `v0.3.0`: README rewrite, changelog update, version bump, release checklist, release notes, release validation, deterministic release hashes, CI determinism, and E2E stability checks.

## Local validation results

| Area | Command | Result |
| --- | --- | --- |
| Shell lint | `make lint` | Passed |
| Formatting | `make fmt-check` | Passed |
| Bats tests | `make test` | Passed: 75 tests |
| CI-equivalent local gate | `make validate` | Passed |
| Installer dry-run | `CI=true bash scripts/install-codex-ubuntu.sh --dry-run --skip-docker --skip-optional` | Passed |
| Release tag contract | `bash scripts/validate-release.sh v0.3.0` | Passed |
| Release artifacts | `bash scripts/release.sh --skip-validate` | Passed |
| Checksum validation | `bash scripts/verify-release-artifacts.sh dist` | Passed |
| Reproducible hashes | `make release-reproducible` | Passed |
| E2E plan stability | `make e2e-dry-run` | Passed |

## Deterministic release evidence

The release builder archived the committed Git tree, extracted it into a temporary staging directory, wrote a sorted POSIX tar stream, normalized owner and group to `0`, removed atime and ctime PAX metadata, set a fixed UTC mtime, and compressed with `gzip -n`.

The final local release build reported a reproducibility hash during `scripts/release.sh --skip-validate`. `make release-reproducible` rebuilt `dist.repro-a` and `dist.repro-b` and compared the generated `zcodex-v0.3.0.tar.gz` archives successfully.

## E2E isolation evidence

The E2E runner starts Ubuntu containers with isolated `HOME`, `TMPDIR`, `XDG_CACHE_HOME`, `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_STATE_HOME`, `npm_config_cache`, `npm_config_prefix`, `ZCODEX_STATE_HOME`, and `ZCODEX_TMP_DIR`. Dry-run mode printed the sorted scenario plan for Ubuntu 22.04 amd64 and Ubuntu 24.04 arm64.

Full container E2E execution was not run in this environment because Docker is not installed. The release remains prepared for full E2E execution in the GitHub Actions `e2e` workflow or any Docker-enabled release host.

## Runtime fixture evidence

Runtime fixtures are generated deterministically and cover clean systems, apt-managed runtime, NodeSource runtime, nvm runtime, broken npm, stale runtime, corrupted manifest, interrupted install, path shadowing, conflicting runtime, and missing runtime conditions. The Bats suite validated fixture isolation, npm cache and prefix isolation, corrupted-manifest rejection, missing-runtime behavior, and fixture-matrix coverage.

## Security hardening evidence

The prepared release keeps security-sensitive operations centralized in dedicated helpers, rejects unsafe command lookup behavior, validates runtime ownership before mutation, uses rollback backups for managed user files, verifies checksum manifests, and documents unsigned-artifact limitations.

## Release decision

`v0.3.0` is prepared for public release. The local validation gates passed, deterministic release hashes were verified, the `v0.3.0` tag points to the release-preparation commit, and remaining publication work is limited to pushing the tag and confirming the GitHub release workflow output.
