# CI stabilization report

The workflow set is split into focused files: `ci.yml`, `e2e.yml`, `release-validate.yml`, and `release.yml`. Each workflow uses a deterministic concurrency group based on workflow name and ref with cancellation enabled, and every job is capped at 30 minutes.

CI keeps Bats, ShellCheck, shfmt, workflow policy, and E2E dry-run validation separate from release publication. Runtime-sensitive tests use fixtures instead of GitHub runner Node.js/npm state, reducing flakes from PATH shadows, npm ownership differences, and cache restore behavior.
