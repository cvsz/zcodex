# E2E validation

Run containerized E2E validation with `scripts/e2e-runner.sh`. The runner supports Ubuntu `22.04` and `24.04` on `amd64` and `arm64` Docker platforms.

Examples:

```bash
scripts/e2e-runner.sh --dry-run --ubuntu 24.04 --arch amd64
scripts/e2e-runner.sh --ubuntu 22.04 --arch arm64 --scenario fresh-install
```

Scenarios are listed in `tests/e2e/scenarios.tsv` and cover fresh install, interrupted recovery, repair mode, manifest reconciliation, strict mode, CI mode, and runtime conflict handling.

The runner enforces a per-scenario timeout, removes containers after execution, writes logs under `artifacts/e2e/`, and preserves failure artifacts for debugging.
