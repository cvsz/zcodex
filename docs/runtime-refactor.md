# Bash Runtime Architecture Review and Refactor Plan

This note records the Bash runtime audit and the refactor direction for keeping `zcodex` Bash-first while reducing global mutable state.

## Architecture review

### Global variables

The runtime intentionally keeps a small compatibility layer of exported environment inputs such as `LOG_FILE`, `CI_MODE`, `ZCODEX_STATE_HOME`, `ZCODEX_STATE_DIR`, `ZCODEX_INSTALL_ID`, and installer flags. Before this refactor, those values were read directly across multiple libraries. The highest-coupling paths were:

- Entry-point path variables (`SCRIPT_DIR`, `LIB_DIR`, `SCRIPT_NAME`) shared with sourced code.
- Installer flags (`DRY_RUN`, `SKIP_DOCKER`, `SKIP_OPTIONAL`) mutated during parsing and then read by later phases.
- State storage (`ZCODEX_STATE_HOME`, `ZCODEX_STATE_DIR`, `ZCODEX_INSTALL_ID`) mutated inside `state_init` and then assumed by phase, manifest, and repair helpers.
- Release orchestration logging (`LOG_FILE`) passed implicitly to subprocesses.

The current direction is to keep environment variables as the external API, but move internal names toward `ZCODEX_*` namespaces and add explicit `_in` functions for state paths.

### Trap usage

The installer uses a single `EXIT` trap for cleanup, state finalization, manifest writes, lock release, temporary directory cleanup, and rollback. That is operationally simple but risky if future libraries install their own `EXIT` trap. `runtime_trap_install_exit` now centralizes trap installation and warns before replacing an existing handler.

### Mutable shared state

Shared mutable state is still present where Bash makes it pragmatic: parser flags, install phase state on disk, backup roots, and security lock descriptors. The safer rule is now:

1. Use namespaced globals for externally configurable process state.
2. Pass state directories and phase values explicitly in reusable library functions.
3. Keep compatibility wrappers only at entry-point boundaries.

### Subprocess-heavy paths

The runtime mostly shells out to stable Unix tools (`date`, `cat`, `chmod`, `install`, `tee`, `curl`, `sha256sum`, `awk`, `stat`, `tr`, `apt-get`, `npm`, `docker`). This is acceptable for an installer, but hot paths should avoid repeated process creation. Specific examples:

- State helpers compute paths with functions for readability; callers that write multiple files should use `_in` variants to avoid implicit lookups.
- Release orchestration now uses `runtime_exec_logged` so tee/PIPESTATUS handling is not duplicated.
- Command discovery uses `runtime_command_exists` where shared orchestration code needs a reusable wrapper.

## Shell refactor plan

### Near term

- Keep `scripts/install-codex-ubuntu.sh` thin and namespaced.
- Keep `codex.sh` outside the full installer runtime, but share only the tiny `exec.sh` library.
- Move state operations toward `state_*_in state_home state_dir ...` signatures.
- Route future command execution through `runtime_exec_logged` or purpose-built wrappers that accept arrays.
- Keep one installer `EXIT` trap installed through `runtime_trap_install_exit`.

### Medium term

- Convert installer parser output into a simple runtime context string or file instead of many process globals.
- Pass context values to phase functions as arguments where it improves clarity.
- Add tests for trap replacement warnings, explicit state directory operations, and logged execution exit-code propagation.
- Add shellcheck rules/tests for un-namespaced uppercase globals in new code.

### Long term

- Keep Bash as the operator-facing entry point.
- Consider migrating only data-heavy manifest/state formatting to a small helper if JSON complexity grows.
- Avoid introducing a shell framework, dependency manager, or DSL unless repeated production incidents show Bash cannot safely express the workflow.

## Implementation examples

### Explicit state passing

```bash
state_mark_in "${ZCODEX_STATE_HOME}" "${ZCODEX_STATE_DIR}" INSTALL "install core runtime" running
state_complete_phase_in "${ZCODEX_STATE_HOME}" "${ZCODEX_STATE_DIR}" INSTALL
```

The compatibility wrappers still exist:

```bash
state_mark INSTALL "install core runtime" running
state_complete_phase INSTALL
```

New reusable code should prefer the `_in` functions when it already has the state directory.

### Reusable command execution

```bash
runtime_exec_logged "${log_file}" "Running Doctor Validation..." bash "${doctor}" --offline
```

This keeps `tee` and `PIPESTATUS` handling in one place while preserving readable shell arrays.

### Safer trap management

```bash
runtime_trap_install_exit installer_cleanup
```

The helper intentionally supports a single active `EXIT` cleanup path. If another handler is present, it logs a warning rather than silently stacking opaque shell strings.

## Maintainability analysis

This refactor keeps the operational shape simple: one installer entry point, one release orchestrator, small libraries, and no new runtime dependency. The main maintainability gain is that path/state-aware functions can now be tested against temporary directories without relying on ambient process globals. The execution wrapper also removes duplicated `tee` pipeline error handling.

The main tradeoff is that Bash cannot fully eliminate mutable state without becoming unreadable. The project should prefer a small set of documented process variables over elaborate context serialization. If a function needs more than a few pieces of context, that is a signal to split the phase or move data formatting out of shell.

## Future migration guidance

- Keep all new globals under `ZCODEX_*` unless a variable is a conventional external input such as `HOME`, `PATH`, or `CI`.
- Add `_in` variants for reusable functions that operate on files, directories, or phase state.
- Keep wrappers for backwards compatibility, but implement new logic in explicit functions.
- Never pass commands as eval strings; use Bash arrays or direct `"$@"` dispatch.
- Keep traps at entry-point boundaries and avoid library-level trap installation.
- Migrate only isolated, data-heavy work to another language; keep orchestration and operator workflows in Bash.
