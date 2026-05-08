# Troubleshooting

## Run a dry run

```bash
CI=true bash scripts/install-codex-ubuntu.sh --dry-run --skip-docker --skip-optional
```

## Validate the local runtime

```bash
bash scripts/doctor.sh
```

## Common issues

### Unsupported OS

The installer supports Ubuntu 22.04 and 24.04 on `x86_64`, `aarch64`, or `arm64`. Use a supported Ubuntu host or container.

### Docker group changes are not active

Log out and log back in after the installer adds your user to the `docker` group.

### Codex command is unavailable

Confirm that npm global binaries are in your `PATH`, then rerun:

```bash
bash scripts/install-codex-ubuntu.sh --skip-docker
```
