# CODEX_COMMIT_INSTRUCTIONS.md – zcodex

## Commit Message Requirements

Use strict Conventional Commits:

<type>(<scope>): <short imperative summary>

Rules:
- Subject line <= 72 chars
- Use imperative mood
- Explain operational impact
- Mention security implications when relevant
- Mention infrastructure or deployment impact when relevant
- No emojis
- No placeholder text

Allowed types:
- feat
- fix
- refactor
- perf
- security
- chore
- docs
- test
- style
- revert

Example:

feat(installer): harden retry execution and locking

- Replaced unsafe bash -c retry execution
- Added flock-based locking
- Improved deterministic install behavior
- Fixed shell injection risks

Closes #123
