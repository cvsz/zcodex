# Troubleshooting

## Run a dry run

```bash
CI=true bash scripts/install-codex-ubuntu.sh --dry-run --skip-docker --skip-optional
```

## Validate the local runtime

```bash
bash scripts/doctor.sh
```

Doctor mode checks platform support, executable lookup path safety, supported interactive shells, sudo readiness for package operations, required runtime commands, optional Docker availability, network access to the Codex package registry, and installed tool versions. In airgapped or proxied environments, use offline mode to skip the outbound network probe:

```bash
bash scripts/doctor.sh --offline
```

Use repair mode to recreate a missing Codex config, restrict existing config permissions, and reapply idempotent shell profile integration without installing packages:

```bash
bash scripts/doctor.sh --repair
```

## Common issues

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
