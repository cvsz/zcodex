# Runtime Ownership and Conflict Resolution

## Architecture proposal

`zcodex` keeps the installer Bash-first, but now treats Node.js and npm as owned runtimes rather than anonymous commands in `PATH`. The installer performs a runtime audit before package installation and classifies the active `node` and `npm` binaries into one ownership domain:

- `system-apt-distro`: Ubuntu/Debian packages own the active binary. For `npm`, package ownership is verified with `dpkg-query -S` so distro `npm` is not mistaken for NodeSource ownership.
- `system-apt-nodesource`: NodeSource `nodejs` package owns the active binary.
- `user-nvm`: the active binary resolves below `NVM_DIR` or `${HOME}/.nvm`.
- `user-asdf`: the active binary resolves below `ASDF_DIR`, `${HOME}/.asdf`, or an asdf shim path.
- `system-unowned`: the binary is in a system path but no recognized `nodejs` or `npm` package owns it.
- `unknown`: the binary is outside recognized ownership roots.
- `absent`: no executable is visible.

The audit phase records and validates:

1. nvm and asdf presence.
2. apt-managed `nodejs` presence.
3. NodeSource package/source presence.
4. distro `npm` package presence.
5. all `node` and `npm` binaries visible in `PATH`.
6. package ownership for the active `node` and `npm` binaries.
7. npm ownership alignment with the active `node` binary.

## Runtime modes

| Mode | Intended environment | Node.js/npm mutation policy | Safe installer decision |
| --- | --- | --- | --- |
| `clean-system` | Fresh Ubuntu host or container where zcodex may manage packages | May install apt `nodejs`/`npm`; refuses to touch nvm/asdf-owned binaries | Install through apt only after the audit finds no dangerous conflicts |
| `existing-runtime` | Workstation with an already activated runtime | Does not install or modify Node.js/npm | Requires compatible `node` and matching `npm`; refuses absent or wrong-version runtime |
| `ci` | CI image with pre-baked runtime | Does not install or modify Node.js/npm | Requires `node` and `npm` in the image; `--ci` selects this mode automatically |
| `developer` | Maintainer workflow with explicit local runtime | Does not install or modify Node.js/npm by default | Same validation as `existing-runtime`, with an opt-in escape hatch for global npm writes |

Global npm package installation into nvm/asdf is blocked by default. Operators may set `ZCODEX_ALLOW_USER_RUNTIME_MUTATION=true` only after explicitly accepting that mutation of their user-managed runtime is desired.

## Conflict matrix

| Detected condition | Severity | Reason | Remediation guidance |
| --- | --- | --- | --- |
| nvm plus apt-managed `nodejs` | Fatal | `PATH` and npm prefix can switch between user and system ownership during install | Use `--runtime-mode existing-runtime` with nvm active, or remove apt `nodejs`/`npm` before clean-system install |
| asdf plus apt-managed `nodejs` | Fatal | asdf shims can shadow apt binaries and cause npm to write into a different prefix | Use `--runtime-mode existing-runtime` with asdf active, or remove apt `nodejs`/`npm` |
| NodeSource `nodejs` plus distro `npm` | Fatal | distro npm is not guaranteed compatible with NodeSource Node.js | Remove distro `npm`, use one NodeSource/npm ownership path, or use a single user-managed runtime |
| `node` and `npm` from different ownership domains | Fatal | global package installs could write to a different runtime than the one being validated | Adjust `PATH` so both commands resolve to the same owner |
| Multiple `node` binaries in `PATH` | Warning | First binary is deterministic, but shell/profile changes could expose a different binary later | Put only the intended provider first in `PATH` |
| Inactive nvm/asdf is present while another owner is active | Warning unless apt `nodejs` is also installed | The manager is detectable but is not currently controlling `node`; future shell initialization may change ownership | Activate the intended manager and use `existing-runtime`, or keep the system path intentionally first |
| Multiple `npm` binaries in `PATH` | Warning | npm prefix may change if `PATH` order changes | Put only the matching npm provider first in `PATH` |
| Existing-runtime mode without `node` or `npm` | Fatal | Installer is not allowed to create a runtime in that mode | Activate/install the runtime before rerunning |
| Existing-runtime mode with wrong Node.js major | Fatal | Codex install is pinned to the reviewed Node.js major | Activate a compatible Node.js version or use clean-system mode on a clean host |
| Clean-system mode with unowned or unknown active binaries | Fatal | The installer cannot prove which prefix global npm writes would mutate | Remove unmanaged binaries from `PATH` or rerun with a verifiable existing runtime |
| CI mode with wrong Node.js major | Fatal | CI must be reproducible and should not install runtimes during the job | Bake the pinned Node.js major and matching npm into the image |
| Active `npm` has unverifiable package ownership | Warning, or fatal when paired with clean-system unowned ownership | npm prefix/package ownership is ambiguous | Use distro/NodeSource packages consistently, or use nvm/asdf with the matching `npm` active |

## Shell implementation

The implementation lives in `scripts/lib/nodejs.sh` and is invoked from the installer before any Node.js/npm package mutation. Important entry points are:

- `nodejs_runtime_audit`: prints a deterministic key/value audit of command paths, versions, ownership, package manager state, and path shadows.
- `nodejs_runtime_conflict_report`: converts the audit into `fatal` or `warn` records with explicit remediation text.
- `nodejs_runtime_audit_phase`: logs audit results, fails early when dangerous conflicts exist in strict install mode, and can report those conflicts non-fatally for dry-runs.
- `nodejs_install_managed`: installs Node.js/npm only in `clean-system` mode and only when the active runtime is not user-managed.
- `nodejs_install_global_packages`: refuses nvm/asdf global writes unless `ZCODEX_ALLOW_USER_RUNTIME_MUTATION=true` is set.

The installer exposes `--runtime-mode clean-system|existing-runtime|ci|developer`; `--ci` remains supported and selects `ci` mode. Dry-runs execute the same input validation and runtime audit, but report install-blocking runtime conflicts as warnings because no Node.js/npm mutation will occur. Non-dry-run installs still fail on those conflicts before locks, backups, apt writes, npm writes, Docker changes, or shell configuration can proceed.

## Migration strategy

1. Existing unattended installs continue to default to `clean-system`.
2. Workstations with nvm/asdf should switch to `--runtime-mode existing-runtime` and activate the desired Node.js version before running the installer.
3. CI images should either use `--ci` or `--runtime-mode ci` and bake the pinned Node.js major into the image.
4. Developers who intentionally install Codex into nvm/asdf should use `--runtime-mode developer` and set `ZCODEX_ALLOW_USER_RUNTIME_MUTATION=true` only for that run.
5. Hosts currently mixing NodeSource `nodejs` and distro `npm` should normalize to one provider before rerunning the installer.
6. Hosts with historical `/usr/local/bin/node` or `/usr/local/bin/npm` installs should remove those binaries from `PATH`, replace them with a package-manager-owned runtime, or explicitly run in `existing-runtime` after verifying ownership.

## UX improvements

The installer now prints the runtime policy in the dry-run plan and logs a concise audit summary before install. Non-dry-run fatal conflicts include a direct remediation sentence and stop the install; dry-runs downgrade those blockers to remediation warnings so CI smoke checks can validate the plan without mutating a polluted runner. Tolerable `PATH` shadows are warnings with the observed binary order. This makes failures actionable without requiring operators to infer ownership from raw package-manager output.

## Security considerations

- The installer fails before privileged apt or global npm writes when runtime ownership is ambiguous.
- User-managed runtime mutation is denied by default to avoid modifying developer home-directory toolchains unexpectedly.
- The implementation avoids shell `eval` and keeps command execution as direct argv dispatch.
- `PATH` shadow detection reduces the risk of validating one binary while installing through another.
- npm ownership verification reduces the chance of privilege boundary mistakes such as running `sudo npm` against a user-managed prefix.
