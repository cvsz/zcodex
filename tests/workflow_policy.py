#!/usr/bin/env python3
"""Validate CI workflow choices that keep Bats execution deterministic."""

from __future__ import annotations

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
WORKFLOW_DIR = REPO_ROOT / ".github" / "workflows"

# These tokens identify the third-party Bats helper/cache setup path that has
# produced noisy tar restore warnings for helper libraries such as bats-assert,
# bats-detik, bats-file, and bats-support. Cache keys or paths for those
# helpers are also blocked so a manual actions/cache step cannot restore
# archives into /usr/lib.
# The project tests do not load those helpers, so CI should keep using the
# Ubuntu-packaged bats binary installed by apt.
DISALLOWED_TOKENS = (
    "bats-core/bats-action",
    "bats-install:",
    "support-install:",
    "assert-install:",
    "detik-install:",
    "file-install:",
    "support-path:",
    "assert-path:",
    "detik-path:",
    "file-path:",
    "bats-assert",
    "bats-detik",
    "bats-file",
    "bats-support",
    "Linux-X64-bats-",
    "/usr/lib/bats-",
)


def workflow_files(workflow_dir: Path = WORKFLOW_DIR) -> list[Path]:
    """Return GitHub workflow YAML files regardless of extension spelling."""
    return sorted({*workflow_dir.glob("*.yml"), *workflow_dir.glob("*.yaml")})


def find_policy_violations(workflow_dir: Path = WORKFLOW_DIR) -> list[str]:
    """Find workflows that opt into the Bats helper/cache restore path."""
    failures: list[str] = []
    for workflow in workflow_files(workflow_dir):
        content = workflow.read_text(encoding="utf-8")
        for token in DISALLOWED_TOKENS:
            if token in content:
                try:
                    rel_path = workflow.relative_to(REPO_ROOT)
                except ValueError:
                    rel_path = workflow
                failures.append(f"{rel_path}: disallowed Bats cache/helper token: {token}")

    return failures


def main(argv: list[str] | None = None) -> int:
    args = sys.argv[1:] if argv is None else argv
    workflow_dir = Path(args[0]) if args else WORKFLOW_DIR
    failures = find_policy_violations(workflow_dir)

    if failures:
        print("Workflow policy violations found:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1

    print("Workflow policy OK: CI uses apt-installed Bats without helper cache restores.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
