# Troubleshooting

## Run a dry run

```bash
CI=true bash scripts/install-codex-ubuntu.sh --dry-run --skip-docker --skip-optional
```

## Validate the local runtime

```bash
bash scripts/doctor.sh
```

Doctor mode checks platform support, executable lookup path safety, supported interactive shells, sudo readiness for package operations, required runtime commands, optional Docker availability, network access to the Codex package registry, and installed tool versions. Doctor System v2 emits each finding as an independently traceable diagnostic with `check_id`, `severity`, `risk_score`, `message`, `context`, `recommendation`, and `auto_fixable` fields. Risk scores map to severity as follows: 0-20 `INFO`, 21-40 `LOW`, 41-60 `MEDIUM`, 61-80 `HIGH`, and 81-100 `CRITICAL`.

Human mode is the default for interactive runs:

```bash
bash scripts/doctor.sh --offline --mode human
```

CI mode is selected automatically when `CI=true`, or explicitly with `--mode ci`; it emits JSON diagnostics only and avoids formatted log noise:

```bash
CI=true bash scripts/doctor.sh --offline
bash scripts/doctor.sh --offline --mode ci
```

Debug mode includes the readable diagnostic stream plus trace context, recommendations, and the JSON form of each diagnostic:

```bash
bash scripts/doctor.sh --offline --mode debug
```

In airgapped or proxied environments, use offline mode to skip the outbound network probe:

```bash
bash scripts/doctor.sh --offline
```

Use repair mode to recreate a missing Codex config, restrict existing config permissions, and reapply idempotent shell profile integration without installing packages:

```bash
bash scripts/doctor.sh --repair
```

## Common issues


### GitHub Actions Bats cache restore warnings

If a workflow emits tar restore warnings for cache keys such as
`Linux-X64-bats-assert-*`, `Linux-X64-bats-detik-*`, or
`Linux-X64-bats-file-*`, or `Linux-X64-bats-support-*`, remove the
third-party Bats helper setup path and use
the repository workflow pattern instead: install `bats` from the Ubuntu package
manager and run `make workflow-policy` before `make test`. The workflow policy
blocks both the helper actions and cache keys/paths such as `Linux-X64-bats-*`
or `/usr/lib/bats-*`, because those archives can try to extract outside the
workspace on GitHub-hosted runners or into privileged system directories such
as `/usr/lib`. The current Bats tests load only
`tests/test_helper.bash`, so restoring helper-library caches is unnecessary and
can turn a cache hit into noisy `/usr/bin/tar` permission warnings. This policy
scans both `.yml` and `.yaml` workflow files and also rejects the helper action
inputs (`support-install`, `assert-install`, `detik-install`, `file-install`,
and their `*-path` variants), not just the action name, so renamed or manually
expanded workflow snippets cannot reintroduce privileged `/usr/lib/bats-*`
cache restores.

### Unsupported OS

The installer supports Ubuntu 22.04 and 24.04 on `x86_64`, `aarch64`, or `arm64`. Use a supported Ubuntu host or container.

### Docker group changes are not active

Log out and log back in after the installer adds your user to the `docker` group.

### PATH is unsafe or incomplete

Remove empty `PATH` entries such as leading, trailing, or repeated colons because they resolve to the current directory. Also remove group-writable or world-writable directories from executable lookup paths before rerunning doctor mode.

### Codex command is unavailable

Confirm that npm global binaries are in your `PATH`, then rerun:

```bash
bash scripts/install-codex-ubuntu.sh --skip-docker
```

### Restore a backed-up config or shell profile

Find the latest backup directory and copy the saved file back to its original path. For example, if `${HOME}/.codex/config.toml` was overwritten, restore `${HOME}/.zcodex/backups/<timestamp>/<home-path>/.codex/config.toml` to `${HOME}/.codex/config.toml`, then run doctor mode again.

## Deterministic diagnostics and failure bundles

`scripts/diagnostics.sh` writes a deterministic failure bundle under
`diagnostics/` by default. The bundle contains:

- `runtime-snapshot.json` with command versions and hashed PATH details;
- `state-snapshot.json` with phase/status and state-history digest;
- `manifest-snapshot.json` when a readable manifest exists;
- the raw manifest and installer log when present.

The tarball uses sorted entries, normalized owner/group metadata, UTC timestamps,
and `gzip -n`. Set `SOURCE_DATE_EPOCH` to reproduce bundle mtimes exactly across
machines.
