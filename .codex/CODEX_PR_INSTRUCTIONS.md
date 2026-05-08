# CODEX_PR_INSTRUCTIONS.md – zcodex

## Pull Request Requirements

Every PR must include:

- Summary
- Technical changes
- Security considerations
- Operational impact
- Rollback strategy
- Validation steps

PR titles must use Conventional Commits.

Example:

fix(installer): harden installer retry and locking behavior

Required validation:

```bash
bash -n scripts/*.sh
shellcheck scripts/*.sh
shfmt -d scripts
```

Security checklist:
- No shell injection risks
- No unsafe eval usage
- No leaked secrets
- No unsafe curl | sh patterns
- Deterministic dependency installation
