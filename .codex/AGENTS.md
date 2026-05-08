# zcodex Codex Agent Notes

- Prefer direct source edits over patch blobs.
- Keep installer behavior modular: orchestration belongs in `scripts/install-codex-ubuntu.sh`; reusable logic belongs in `scripts/lib/`.
- Run shell syntax checks, shellcheck, formatting checks, and tests before opening a PR when tools are available.
