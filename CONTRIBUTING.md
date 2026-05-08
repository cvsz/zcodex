# Contributing to zcodex

Thanks for helping improve `zcodex`. This project favors small, auditable shell changes, explicit runtime behavior, and documentation that operators can trust.

## Project principles

- Keep the installer modular: orchestration belongs in `scripts/install-codex-ubuntu.sh`; reusable behavior belongs in `scripts/lib/`.
- Prefer deterministic behavior over host-specific magic.
- Avoid `curl | bash` patterns and other hidden execution paths.
- Keep documentation concise, accurate, and aligned with the current scripts.
- Make the smallest credible change that solves the problem.

## Development setup

Clone the repository and run validation from the repository root:

```bash
git clone https://github.com/cvsz/zcodex.git
cd zcodex
make validate
```

Optional tools used by the validation targets:

- `shellcheck`
- `shfmt`
- `bats`
- `bash`

On Ubuntu, install them with:

```bash
sudo apt-get update
sudo apt-get install -y bats shellcheck shfmt
```

## Common commands

```bash
make lint            # shellcheck for scripts and tests
make fmt-check       # verify shfmt formatting
make fmt             # rewrite shell formatting
make test            # run Bats tests
make doctor          # inspect local runtime health
make validate        # lint + formatting + tests
```

Installer dry runs are preferred for PRs that change install behavior:

```bash
CI=true bash scripts/install-codex-ubuntu.sh --dry-run --skip-docker --skip-optional
```

## Pull request expectations

Before opening a pull request:

1. Keep the branch focused on one behavior, bug fix, or documentation improvement.
2. Update documentation when behavior, flags, phases, supported platforms, or release steps change.
3. Run `make validate` when the required tools are available.
4. Include any environment limitations in the PR description.
5. Avoid committing generated `dist/` artifacts, logs, secrets, or local machine state.

## Shell style

- Use Bash for project scripts.
- Keep functions small and named for their domain.
- Quote variables unless word splitting is intentional.
- Prefer arrays for command construction.
- Do not wrap imports or source statements in broad defensive patterns that hide failures.
- Keep security-sensitive helpers centralized in `scripts/lib/security.sh`.

## Tests

Bats tests live in `tests/`. Add tests for changes that affect parsing, state transitions, manifests, runtime detection, release checks, or installer behavior. If a behavior is hard to test safely, document the manual validation command in the PR.

## Documentation changes

Documentation should be operational, not promotional. When adding a feature or changing behavior, update the relevant files under `docs/`, the README quick path, and the changelog when the change is user-visible.

## Release contributions

Release changes must preserve the release contract:

- `VERSION` is the source of truth.
- Tags use `vX.Y.Z`.
- `CHANGELOG.md` contains a matching `## vX.Y.Z` section.
- Release artifacts are generated from a committed Git ref.
- Checksums are generated and verified before publication.

See `docs/release.md` and `docs/release-checklist.md` for details.

## Security reports

Do not open public issues for vulnerabilities. Follow `SECURITY.md`.
