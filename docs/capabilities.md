# Runtime Capability Layer

`zcodex` remains Ubuntu-first, but installer decisions now flow through a small runtime capability registry instead of direct distro branching. The capability layer answers what the host can do, while the installer keeps one deterministic package path.

## Architecture design

The layer lives in `scripts/lib/platform.sh` and is loaded by `scripts/lib/runtime.sh` before package, Node.js, and Docker helpers. It has three responsibilities:

1. Identify stable host facts such as OS release text, architecture, WSL status, and container context.
2. Register the runtime capabilities the installer is allowed to depend on.
3. Validate that the host has the minimum capability set for the current Ubuntu-first bootstrap path.

The installer still prefers Ubuntu 22.04 and 24.04. Non-Ubuntu systems do not receive custom branches or hidden package plans; if they expose the required capabilities, zcodex emits an explicit unsupported best-effort warning and runs the same managed APT flow. If the APT capability is absent, validation fails before package operations begin.

## Capability model

The registry exposes four boolean capabilities:

| Capability | Meaning | Current detector |
| --- | --- | --- |
| `supports_apt` | The host can run the managed package path. | `apt-get` and `dpkg-query` are present. |
| `supports_systemd` | Services can be managed through systemd. | `systemctl` exists and `/run/systemd/system` is present, or `ZCODEX_ASSUME_SYSTEMD=true` is set for deterministic tests. |
| `supports_docker` | Docker is already available or can be installed through the managed package path. | `docker` exists, otherwise `supports_apt` is true. |
| `supports_rootless` | User-scoped configuration is safe to perform without running as root. | The process is non-root, `HOME` is writable, and `sudo` exists. |

The registry is intentionally small. New operating systems should not add distro-specific branches; they should add or refine capability detectors only when an installer phase needs a new primitive.

## Shell examples

Inspect the registry:

```bash
. scripts/lib/platform.sh
runtime_capability_registry
```

Gate package work on the package capability:

```bash
if ! supports_apt; then
  log_error "APT capability is required for managed package installation."
  return 1
fi
packages_install curl git jq
```

Gate service management separately from package installation:

```bash
packages_install docker.io docker-compose-plugin
if supports_systemd; then
  sudo systemctl enable --now docker
else
  log_warn "Skipping Docker service enablement because systemd is unavailable."
fi
```

Keep Ubuntu-first behavior without turning OS identity into the install switch:

```bash
platform_validate
# Ubuntu 22.04/24.04: success log.
# Capability-compatible non-Ubuntu: unsupported best-effort warning.
# Missing APT capability or unsupported architecture: deterministic failure.
```

## Migration strategy

1. Keep `scripts/install-codex-ubuntu.sh` as the stable entry point while moving decisions into capability functions.
2. Convert package, Node.js, and Docker helpers to call `supports_apt`, `supports_systemd`, and `supports_docker` before doing work.
3. Preserve backward-compatible wrapper function names during the transition so existing local automation that sources helpers does not break immediately.
4. Record capabilities in the manifest so support requests can explain why an installer path was chosen.
5. Add future portability by introducing narrow capabilities, not distro matrices. For example, a future alternate package manager should become a new managed package capability and package helper, not a giant `case ID in ...` block.

## Maintainability analysis

The registry keeps policy and mechanism separate. Platform facts are still observable for logging and support, but installer behavior is driven by the capabilities required by each phase. This reduces repeated OS checks, makes dry runs more informative, and keeps unsupported hosts deterministic: either required primitives exist and the same flow runs, or validation stops early with a clear error.

The tradeoff is that capability-compatible non-Ubuntu systems may still fail later if their repositories do not carry the expected package versions. That is acceptable for zcodex because portability is future-facing and Ubuntu remains the primary support target. The design avoids promising broad distro support while leaving a clean extension point for specific, tested capabilities.
