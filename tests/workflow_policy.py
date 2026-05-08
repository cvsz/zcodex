#!/usr/bin/env python3
"""Validate CI workflow choices that keep Bats execution deterministic."""

from __future__ import annotations

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
WORKFLOW_DIR = REPO_ROOT / ".github" / "workflows"

# These tokens identify the third-party Bats helper/cache setup path that has
# produced noisy tar restore warnings for helper libraries such as bats-assert,
# bats-detik, and bats-file. The project tests do not load those helpers, so CI
# should keep using the Ubuntu-packaged bats binary installed by apt.
DISALLOWED_TOKENS = (
    "bats-core/bats-action",
    "bats-assert",
    "bats-detik",
    "bats-file",
)


def main() -> int:
    failures: list[str] = []
    for workflow in sorted(WORKFLOW_DIR.glob("*.yml")):
        content = workflow.read_text(encoding="utf-8")
        for token in DISALLOWED_TOKENS:
            if token in content:
                rel_path = workflow.relative_to(REPO_ROOT)
                failures.append(f"{rel_path}: disallowed Bats cache/helper token: {token}")

    if failures:
        print("Workflow policy violations found:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1

    print("Workflow policy OK: CI uses apt-installed Bats without helper cache restores.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
