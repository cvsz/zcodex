#!/usr/bin/env python3
"""Regression guard for the fail-closed GitHub security workflow."""

from __future__ import annotations

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
WORKFLOW_PATH = REPO_ROOT / ".github" / "workflows" / "security.yml"


def main() -> int:
    if not WORKFLOW_PATH.is_file():
        print(f"Missing security workflow: {WORKFLOW_PATH}", file=sys.stderr)
        return 1

    content = WORKFLOW_PATH.read_text(encoding="utf-8")
    required = (
        "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1",
        "gitleaks/gitleaks-action@e0c47f4f8be36e29cdc102c57e68cb5cbf0e8d1e",
        "semgrep/semgrep@sha256:451b3d875c00dac7ed5db5293e584a07de11449a409c10b3c2d2652f429630b6",
        "github/codeql-action/upload-sarif@9b3254085494b55a0f7c4c2b3d2d52cc712ce370",
        "actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9",
        'GITLEAKS_ENABLE_COMMENTS: "false"',
        'GITLEAKS_ENABLE_UPLOAD_ARTIFACT: "false"',
        "pull-requests: read",
        "security-events: write",
        "--read-only",
        "--cap-drop=ALL",
        "--security-opt=no-new-privileges:true",
        "--metrics=off",
        "test -s semgrep.sarif",
    )
    forbidden = (
        "|| true",
        "continue-on-error: true",
        "pull_request_target:",
        "actions/checkout@v4",
        "actions/upload-artifact@v4",
        "github/codeql-action/upload-sarif@v3",
    )

    failures: list[str] = []
    for token in required:
        if token not in content:
            failures.append(f"missing required security control: {token}")

    for token in forbidden:
        if token in content:
            failures.append(f"forbidden fail-open or outdated workflow token: {token}")

    sarif_check = content.find("test -s semgrep.sarif")
    sarif_upload = content.find("github/codeql-action/upload-sarif@")
    if sarif_check < 0 or sarif_upload < 0 or sarif_check > sarif_upload:
        failures.append("SARIF must be verified as non-empty before upload")

    if failures:
        print("Security workflow policy violations found:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1

    print("Security workflow policy OK: scanners fail closed and actions/images are pinned.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
