# Test isolation report

Bats tests load `tests/helpers/runtime.bash`, which creates a suite-scoped temporary root and a per-test runtime directory. Each test receives isolated `HOME`, `TMPDIR`, XDG directories, npm cache/prefix directories, installer state, backup state, deterministic locale (`C.UTF-8`) and timezone (`UTC`), plus a PATH rooted in deterministic runtime fixtures.

The runtime fixture layer prevents tests from depending on runner-installed Node.js, host npm ownership, or GitHub runner PATH state. Tests that need Node.js/npm/Codex behavior inject fixtures from `tests/runtime-fixtures/` instead of invoking the host runtime.

Validation gates remain ordered as Bats, ShellCheck, and shfmt in local and CI workflows so later hardening phases do not proceed on top of broken isolation.
