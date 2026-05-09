# zcodex Codex Agent Notes

These instructions apply to all files under `.codex/`.

## Mission & Operating Model

- Produce secure, deterministic, and auditable changes.
- Prefer explicit, minimal, reviewable diffs over broad transformations.
- Treat all external inputs as untrusted unless explicitly marked trusted.
- Do not assume runtime, credentials, secrets, or network topology beyond what is explicitly provided.
- Prefer PR-oriented workflows and traceable commits.

## Change Management

- Keep scope tightly aligned to the user request.
- Avoid incidental refactors unless they are required for correctness or security.
- Preserve backward compatibility unless the user requests a breaking change.
- Document non-obvious behavior changes in commit messages and PR body.
- If touching deployment behavior, call out blast radius and rollback strategy.

## Security & Supply Chain Requirements

- Follow dependency hygiene:
  - Pin versions where practical.
  - Avoid introducing unmaintained or unnecessary dependencies.
  - Prefer official/verified sources for downloads.
- Ensure artifact provenance is explainable (what was fetched, from where, and why).
- Prefer reproducible workflows (deterministic scripts, stable ordering, explicit flags).
- Never embed secrets, tokens, or credentials in code, scripts, tests, or examples.
- Validate and sanitize untrusted inputs before use.

## Shell & Script Safety

- Scripts must be POSIX/Bash-safe according to the script's shebang.
- Use safe shell patterns:
  - Quote expansions unless deliberate word-splitting is required and documented.
  - Avoid `eval` unless unavoidable; if used, justify and constrain input strictly.
  - Avoid mutating `IFS` globally.
  - Use `set -euo pipefail` for bash scripts where compatible.
  - Prefer `printf` over `echo` for predictable output.
- Avoid unsafe temporary file handling; use `mktemp` and cleanup traps where needed.

## CI/CD and Infrastructure Guardrails

- Do not self-modify CI/CD pipelines, release workflows, or production deployment config unless the user explicitly requests it.
- If CI/CD files are changed by request, explicitly summarize security and operational implications.
- Keep environment assumptions explicit so behavior is reproducible across CI environments.

## Verification Expectations

Before finalizing changes (when tools are available), run relevant checks:

- Syntax/lint checks (e.g., `bash -n`, `shellcheck`, formatter checks).
- Project tests relevant to modified files.
- Any repository-specific validation commands documented in project docs.

If checks cannot run, clearly state what was skipped and why.

## Documentation in Responses

- Provide concise rationale for security-relevant decisions.
- Include exact commands run for validation and their outcomes.
- Note residual risks, follow-ups, or assumptions when applicable.

## zcodex-specific Structure

- Keep installer orchestration in `scripts/install-codex-ubuntu.sh`.
- Keep reusable shell logic in `scripts/lib/`.
- Prefer direct source edits over generated patch blobs when working locally.
