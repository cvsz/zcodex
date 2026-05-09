#!/usr/bin/env bash
# Run Doctor v2 in CI and publish native JSON, logs, annotations, and gates.

set -Eeuo pipefail

REPORT_DIR="${DOCTOR_REPORT_DIR:-.doctor}"
REPORT_JSON="${REPORT_DIR}/report.json"
REPORT_LOG="${REPORT_DIR}/report.log"
BASELINE_JSON="${DOCTOR_BASELINE_JSON:-${REPORT_DIR}/baseline.json}"
RAW_JSONL="${REPORT_DIR}/report.ndjson"

mkdir -p "${REPORT_DIR}"

set +e
CI=true DOCTOR_OUTPUT_MODE=ci bash scripts/doctor.sh --mode ci "$@" >"${RAW_JSONL}" 2>"${REPORT_LOG}"
doctor_status=$?
set -e

python3 - "${RAW_JSONL}" "${REPORT_LOG}" "${REPORT_JSON}" "${BASELINE_JSON}" "${doctor_status}" <<'PY'
from __future__ import annotations

import datetime as dt
import json
import sys
from pathlib import Path
from typing import Any

raw_path = Path(sys.argv[1])
log_path = Path(sys.argv[2])
report_path = Path(sys.argv[3])
baseline_path = Path(sys.argv[4])
doctor_status = int(sys.argv[5])

SUBSYSTEMS = ("PATH", "runtime", "CI", "security", "filesystem")
SEVERITY_ORDER = {"CRITICAL": 0, "HIGH": 1, "MEDIUM": 2, "LOW": 3, "INFO": 4}
ANNOTATION_LEVEL = {
    "CRITICAL": "error",
    "HIGH": "error",
    "MEDIUM": "warning",
    "LOW": "warning",
    "INFO": "notice",
}


def subsystem_for(issue: dict[str, Any]) -> str:
    check_id = str(issue.get("check_id", ""))
    if check_id.startswith("doctor.path"):
        return "PATH"
    if check_id.startswith(("doctor.ci", "doctor.workflow")):
        return "CI"
    if check_id.startswith(("doctor.permissions", "doctor.shell")):
        return "security"
    if check_id.startswith(("doctor.filesystem", "doctor.manifest", "doctor.config")):
        return "filesystem"
    if check_id.startswith(("doctor.command", "doctor.tooling", "doctor.network", "doctor.platform")):
        return "runtime"
    return "runtime"


def escape_annotation(value: object) -> str:
    text = str(value)
    return (
        text.replace("%", "%25")
        .replace("\r", "%0D")
        .replace("\n", "%0A")
        .replace(":", "%3A")
        .replace(",", "%2C")
    )


def read_issues(path: Path) -> list[dict[str, Any]]:
    issues: list[dict[str, Any]] = []
    if not path.exists():
        return issues
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip():
            continue
        try:
            issue = json.loads(line)
        except json.JSONDecodeError as exc:
            issues.append(
                {
                    "check_id": "doctor.ci.invalid-json",
                    "severity": "CRITICAL",
                    "risk_score": 100,
                    "message": f"Doctor emitted invalid JSON on line {line_number}: {exc}",
                    "context": str(path),
                    "recommendation": "Fix Doctor CI output serialization.",
                    "subsystem": "CI",
                }
            )
            continue
        if isinstance(issue, dict):
            issue.setdefault("risk_score", 0)
            issue.setdefault("severity", "INFO")
            issue.setdefault("check_id", "doctor.unknown")
            issue.setdefault("message", "Doctor issue")
            issue["subsystem"] = subsystem_for(issue)
            issues.append(issue)
    return issues


def load_baseline(path: Path) -> dict[str, Any] | None:
    if not path.exists():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None
    return data if isinstance(data, dict) else None


issues = read_issues(raw_path)
counts = {severity: 0 for severity in ("INFO", "LOW", "MEDIUM", "HIGH", "CRITICAL")}
for issue in issues:
    counts[str(issue.get("severity", "INFO"))] = counts.get(str(issue.get("severity", "INFO")), 0) + 1

total_risk = sum(int(issue.get("risk_score") or 0) for issue in issues)
top_issues = sorted(
    issues,
    key=lambda issue: (-int(issue.get("risk_score") or 0), SEVERITY_ORDER.get(str(issue.get("severity")), 99), str(issue.get("check_id"))),
)[:5]
subsystems: dict[str, dict[str, int]] = {
    name: {"count": 0, "risk_score": 0, "critical": 0, "high": 0, "warnings": 0}
    for name in SUBSYSTEMS
}
for issue in issues:
    subsystem = str(issue.get("subsystem", "runtime"))
    bucket = subsystems.setdefault(subsystem, {"count": 0, "risk_score": 0, "critical": 0, "high": 0, "warnings": 0})
    severity = str(issue.get("severity", "INFO"))
    risk = int(issue.get("risk_score") or 0)
    bucket["count"] += 1
    bucket["risk_score"] += risk
    if severity == "CRITICAL":
        bucket["critical"] += 1
    elif severity == "HIGH":
        bucket["high"] += 1
    elif severity in {"LOW", "MEDIUM"}:
        bucket["warnings"] += 1

baseline = load_baseline(baseline_path)
if baseline:
    baseline_total = int(baseline.get("summary", {}).get("total_risk_score", baseline.get("total_risk_score", 0)) or 0)
    baseline_critical = int(baseline.get("summary", {}).get("severity_counts", {}).get("CRITICAL", 0) or 0)
    trend = {
        "baseline_exists": True,
        "baseline_path": str(baseline_path),
        "risk_delta": total_risk - baseline_total,
        "critical_delta": counts.get("CRITICAL", 0) - baseline_critical,
    }
else:
    trend = {
        "baseline_exists": False,
        "baseline_path": str(baseline_path),
        "risk_delta": None,
        "critical_delta": None,
    }

ci_failed = counts.get("CRITICAL", 0) > 0 or total_risk > 300
summary = {
    "generated_at": dt.datetime.now(dt.UTC).isoformat(),
    "doctor_status": doctor_status,
    "ci_failed": ci_failed,
    "fail_conditions": {
        "critical_issues": counts.get("CRITICAL", 0),
        "total_risk_score": total_risk,
        "risk_threshold": 300,
    },
    "total_risk_score": total_risk,
    "severity_counts": counts,
    "issue_count": len(issues),
    "top_5_highest_risk_issues": top_issues,
    "trend": trend,
    "subsystem_breakdown": subsystems,
}
report = {"summary": summary, "issues": issues}
report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")

with log_path.open("a", encoding="utf-8") as log:
    log.write("\nDoctor v2 CI summary\n")
    log.write(f"total risk score: {total_risk}\n")
    log.write(f"severity counts: {json.dumps(counts, sort_keys=True)}\n")
    log.write("top 5 highest-risk issues:\n")
    for issue in top_issues:
        log.write(f"- [{issue.get('severity')}] {issue.get('check_id')} risk={issue.get('risk_score')}: {issue.get('message')}\n")
    if baseline:
        log.write(f"trend: risk_delta={trend['risk_delta']} critical_delta={trend['critical_delta']} baseline={baseline_path}\n")
    else:
        log.write(f"trend: no baseline found at {baseline_path}\n")
    log.write("subsystem breakdown:\n")
    for name in SUBSYSTEMS:
        log.write(f"- {name}: {json.dumps(subsystems[name], sort_keys=True)}\n")

print("::group::Doctor v2 summary")
print(f"total risk score: {total_risk}")
print(f"critical issues: {counts.get('CRITICAL', 0)}")
print(f"report: {report_path}")
print(f"log: {log_path}")
print("::endgroup::")

for severity in ("CRITICAL", "HIGH", "MEDIUM", "LOW", "INFO"):
    severity_issues = [issue for issue in issues if str(issue.get("severity")) == severity]
    if not severity_issues:
        continue
    print(f"::group::Doctor {severity} issues")
    for issue in severity_issues:
        level = ANNOTATION_LEVEL.get(severity, "notice")
        title = escape_annotation(f"Doctor {severity}: {issue.get('check_id')}")
        message = escape_annotation(f"risk={issue.get('risk_score')} subsystem={issue.get('subsystem')} {issue.get('message')}")
        print(f"::{level} title={title}::{message}")
    print("::endgroup::")

raise SystemExit(1 if ci_failed else 0)
PY
