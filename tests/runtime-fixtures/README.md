# Runtime fixtures

`tests/runtime-fixtures/` contains deterministic command shims and metadata used to isolate runtime ownership tests from the host runner. Generate the tree with:

```bash
scripts/generate-runtime-fixtures.sh
```

Each fixture may provide:

- `bin/node`, `bin/npm`, `bin/codex`, and `bin/dpkg-query` command shims.
- `ownership/*.owner` files that document the simulated owner of PATH-visible commands.
- Optional manifest or state files for recovery and reconciliation tests.

Fixtures:

- `clean-system`: no active Node.js/npm/Codex runtime ahead of the trusted system PATH.
- `apt-node`: Ubuntu distro-owned Node.js and npm.
- `nodesource-node`: NodeSource-owned Node.js/npm matching the pinned runtime.
- `nvm-node`: user-managed Node.js/npm that must not receive global installs unless explicitly allowed.
- `broken-npm`: working Node.js with npm failing deterministically.
- `stale-runtime`: old Codex CLI plus stale manifest state.
- `corrupted-manifest`: invalid manifest JSON for schema rejection.
- `interrupted-install`: partial install state for recovery tests.
- `path-shadowing`: unsafe PATH shadow command simulation.
- `conflicting-runtime`: mismatched runtime ownership/version state.
- `missing-runtime`: no host Node.js/npm exposed through PATH.
