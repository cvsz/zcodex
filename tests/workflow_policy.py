#!/usr/bin/env python3
"""Validate CI workflow choices that keep CI dependency setup deterministic."""

from __future__ import annotations

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
WORKFLOW_DIR = REPO_ROOT / ".github" / "workflows"

# These tokens identify the third-party Bats helper/cache setup path that has
# produced noisy tar restore warnings for helper libraries such as bats-assert,
# bats-detik, bats-file, and bats-support. Cache keys or paths for those
# helpers are also blocked so a manual actions/cache step cannot restore
# archives into /usr/lib. Deprecated action major versions are blocked so CI
# does not regress to Node.js 20-backed actions after the repository opts into
# Node.js 24 execution. The project tests do not load Bats helper libraries, so
# CI should keep using the Ubuntu-packaged bats binary installed by apt.
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
    "actions/checkout@v4",
    "actions/upload-artifact@v4",
    "actions/cache@",
    "softprops/action-gh-release@v2",
)


def workflow_files(workflow_dir: Path = WORKFLOW_DIR) -> list[Path]:
    """Return GitHub workflow YAML files regardless of extension spelling."""
    return sorted({*workflow_dir.glob("*.yml"), *workflow_dir.glob("*.yaml")})


def workflow_display_path(workflow: Path) -> Path:
    """Return a stable workflow path for policy messages."""
    try:
        return workflow.relative_to(REPO_ROOT)
    except ValueError:
        return workflow


def find_policy_violations(workflow_dir: Path = WORKFLOW_DIR) -> list[str]:
    """Find workflows that opt into blocked dependency/action setup paths."""
    failures: list[str] = []
    for workflow in workflow_files(workflow_dir):
        content = workflow.read_text(encoding="utf-8")
        rel_path = workflow_display_path(workflow)
        for token in DISALLOWED_TOKENS:
            if token in content:
                failures.append(f"{rel_path}: disallowed Bats cache/helper token: {token}")

    return failures


def find_doctor_ci_violations(workflow_dir: Path = WORKFLOW_DIR) -> list[str]:
    """Find workflows missing Doctor v2 CI observability safeguards."""
    failures: list[str] = []
    for workflow in workflow_files(workflow_dir):
        content = workflow.read_text(encoding="utf-8")
        rel_path = workflow_display_path(workflow)
        if "group: doctor-${{ github.ref }}" not in content:
            failures.append(f"{rel_path}: missing Doctor v2 concurrency group")
        if "cancel-in-progress: true" not in content:
            failures.append(f"{rel_path}: missing concurrency cancellation")
        if "timeout-minutes: 30" not in content:
            failures.append(f"{rel_path}: missing 30 minute timeout")
        if "scripts/doctor-ci.sh" not in content:
            failures.append(f"{rel_path}: missing Doctor v2 CI report step")
        if "path: .doctor/" not in content:
            failures.append(f"{rel_path}: missing Doctor v2 report artifact upload")

    return failures


def main(argv: list[str] | None = None) -> int:
    args = sys.argv[1:] if argv is None else argv
    workflow_dir = Path(args[0]) if args else WORKFLOW_DIR
    failures = [
        *find_policy_violations(workflow_dir),
        *find_doctor_ci_violations(workflow_dir),
    ]

    if failures:
        print("Workflow policy violations found:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1

    print("Workflow policy OK: CI avoids Bats helper caches, deprecated actions, and missing Doctor v2 observability gates.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
