# Bash Security Skill

Use this skill when reviewing or fixing shell scripts.

## Purpose

Find and fix risky Bash patterns such as:

- global or unclear IFS usage
- unquoted variable expansion
- unsafe command substitution
- unsafe eval usage
- non-deterministic parsing
- missing strict mode

## Rules

- Prefer `set -Eeuo pipefail` for Bash scripts.
- Prefer arrays for commands.
- Use `"${array[@]}"` for array expansion.
- Avoid global IFS changes.
- Avoid eval and dynamic command execution.
- Treat all external input as untrusted.

## Output Format

1. issue
2. risk
3. safe replacement
4. minimal patch
5. validation command
