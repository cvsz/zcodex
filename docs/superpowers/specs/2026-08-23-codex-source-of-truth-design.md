# Codex Source-of-Truth Consolidation Design

Date: 2026-08-23  
Status: Proposed  
Repository: `cvsz/zcodex`

## Objective

Turn `cvsz/zcodex` into a single integration source of truth for the public Codex ecosystem while preserving the repository's existing launcher, configuration, policy, security, reproducibility, documentation, and test assets.

The four upstream projects remain authoritative for their own development:

- `openai/codex`
- `openai/skills`
- `openai/plugins`
- `openai/codex-universal`

`cvsz/zcodex` becomes authoritative for the pinned combination of those sources, local integration code, validation policy, and releases.

## Non-goals

- Replacing OpenAI's proprietary model weights, Codex cloud, or IDE extension.
- Flattening upstream files into the repository root.
- Automatically merging unreviewed upstream changes.
- Rewriting or deleting existing `cvsz/zcodex` history.
- Publishing modified upstream components without their licenses and attribution.

## Existing Repository Preservation

The current root-level project remains the integration/control plane. Existing files and directories—including `.codex`, `.github`, `config`, `docs`, `opa`, `scripts`, `tests`, `zcodex`, security documentation, reproducibility tooling, launchers, and maintenance scripts—must be preserved unless a later implementation step explicitly migrates them with regression coverage.

Upstream source code is isolated under `components/` to avoid collisions with existing root assets.

## Repository Layout

```text
zcodex/
├── components/
│   ├── codex/
│   ├── skills/
│   ├── plugins/
│   └── codex-universal/
├── integration/
│   ├── patches/
│   └── compatibility/
├── scripts/
│   ├── upstream/
│   └── existing project scripts
├── tests/
│   ├── integration/
│   └── existing project tests
├── docs/
│   ├── architecture/
│   ├── upstream/
│   └── existing documentation
├── UPSTREAMS.yaml
└── existing root files
```

## Import Strategy

Use Git subtrees, one prefix per upstream repository. The initial import preserves upstream history. Subsequent synchronization uses the same prefixes and explicit upstream branches.

Subtrees are preferred over:

- submodules, because clones and archives should contain usable sources without a second checkout step;
- flattened copies, because provenance and upstream synchronization would become ambiguous;
- package-manager-only dependencies, because the goal is a complete, inspectable source integration.

No upstream source is edited directly for local integration needs. Local changes live as documented patches in `integration/patches/<component>/` or as adapters in `integration/compatibility/`. This minimizes update conflicts and makes divergence auditable.

## Upstream Manifest

`UPSTREAMS.yaml` is the machine-readable source of truth. Each component records:

- component name and local prefix;
- upstream repository URL;
- tracked branch;
- pinned commit SHA;
- import timestamp;
- license identifier and license-file path;
- subtree mode and update policy;
- optional patch series and compatibility checks.

Synchronization must fail closed when a repository, branch, commit, license, or expected prefix does not match the manifest.

## Synchronization Flow

1. Fetch the configured upstream branch.
2. Resolve and record the candidate commit.
3. Verify repository identity, commit reachability, and license presence.
4. Update exactly one subtree prefix.
5. Reapply or validate local patch series without silently resolving conflicts.
6. update `UPSTREAMS.yaml`.
7. Run component and integration validation.
8. Produce a reviewable branch and pull request.

Scheduled automation checks for changes and opens pull requests. It never commits directly to `main`, never force-pushes, and never imports from an unconfigured source.

Manual Bash and PowerShell entry points provide equivalent behavior for Linux and Windows maintainers.

## Validation and CI

CI is layered so unrelated toolchains do not obscure failures:

1. **Manifest validation** — schema, pinned SHA, prefix, source URL, and license checks.
2. **Provenance validation** — imported tree corresponds to the declared upstream commit.
3. **Component checks** — invoke supported upstream checks for changed components.
4. **Integration checks** — existing launcher/config/policy behavior plus cross-component smoke tests.
5. **Security checks** — secret scanning, dependency review, CodeQL where applicable, and existing policy tests.
6. **Reproducibility checks** — deterministic source inventory, checksums, and build metadata.
7. **License checks** — retain upstream license files and generate a combined notice/inventory.

Path filtering should run expensive component jobs only when their subtree, patch series, manifest entry, or integration adapter changes. A final required aggregate gate reports the status of every applicable layer.

## Security Boundaries

Upstream content is untrusted input until validated. Synchronization scripts must:

- use fixed repository allowlists from `UPSTREAMS.yaml`;
- avoid evaluating upstream-provided shell fragments;
- use explicit temporary directories;
- reject dirty worktrees for local update operations;
- reject unexpected symlinks or paths that escape their component prefix;
- avoid credentials in command output and generated artifacts;
- pin GitHub Actions by immutable commit SHA where practical;
- require pull-request review and protected-branch checks before integration.

Automation permissions use least privilege: read-only contents for detection and narrowly scoped pull-request/branch write access only for the update job.

## Releases and Versioning

The repository has its own integration version independent of upstream versions. Each release records:

- the integration version;
- all four pinned upstream commits;
- applied local patch identifiers;
- validation and security evidence;
- source checksums and license inventory.

A release is a tested composition, not a claim that the upstream projects share a single version.

## Error Handling and Recovery

- Import or update conflicts stop the operation and leave a reviewable branch.
- Failed validation prevents PR auto-merge and release creation.
- A previous manifest and Git commit provide rollback without mutating upstream history.
- Partial imports are never committed as a successful synchronization.
- Automation emits a concise summary identifying the component, candidate SHA, completed checks, and blocker.

## Delivery Sequence

1. Establish manifest schema and validation tests.
2. Add safe cross-platform synchronization tooling.
3. Import `openai/codex`.
4. Import `openai/skills`.
5. Import `openai/plugins`.
6. Import `openai/codex-universal`.
7. Add integration, provenance, license, and security gates.
8. Add scheduled update-PR automation.
9. Update unified documentation and produce the first integration release candidate.

Each import is a separate reviewable commit or pull request. This bounds risk and permits rollback by component.

## Acceptance Criteria

- A normal clone contains all four component trees without submodule initialization.
- Existing `cvsz/zcodex` behavior and assets remain present.
- Every imported tree has traceable repository, branch, commit, and license metadata.
- Linux and Windows maintainers can detect and prepare upstream updates.
- CI detects manifest drift, provenance mismatches, unsafe paths, missing licenses, and integration regressions.
- Upstream updates arrive as pull requests and cannot bypass protected `main`.
- The repository can produce a reproducible source inventory for a pinned integration version.
