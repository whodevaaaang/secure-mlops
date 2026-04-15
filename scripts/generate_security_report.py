#!/usr/bin/env python3
"""Aggregate security scan outputs into JSON and HTML summaries."""

from __future__ import annotations

import json
from datetime import datetime, timezone
from html import escape
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
REPORT_DIR = ROOT / "security" / "reports" / "generated"


def load_json(path: Path) -> dict:
    if not path.exists():
        return {"status": "missing", "path": str(path.relative_to(ROOT))}
    try:
        return json.loads(path.read_text())
    except json.JSONDecodeError as exc:
        return {
            "status": "invalid",
            "path": str(path.relative_to(ROOT)),
            "error": str(exc),
        }


def summarize_gitleaks(report: dict) -> dict:
    if isinstance(report, dict) and report.get("status") in {"missing", "invalid"}:
        return {
            "tool": "gitleaks",
            "status": report["status"],
            "count": 0,
            "details": report,
            "sample": [],
        }
    findings = report if isinstance(report, list) else []
    return {
        "tool": "gitleaks",
        "status": "ok" if not findings else "findings",
        "count": len(findings),
        "sample": findings[:5],
    }


def summarize_bandit(report: dict) -> dict:
    if isinstance(report, dict) and report.get("status") in {"missing", "invalid"}:
        return {
            "tool": "bandit",
            "status": report["status"],
            "count": 0,
            "details": report,
            "sample": [],
        }
    results = report.get("results", []) if isinstance(report, dict) else []
    severity = {"LOW": 0, "MEDIUM": 0, "HIGH": 0}
    for item in results:
        sev = item.get("issue_severity", "LOW")
        severity[sev] = severity.get(sev, 0) + 1
    return {
        "tool": "bandit",
        "status": "ok" if not results else "findings",
        "count": len(results),
        "severity": severity,
        "sample": results[:5],
    }


def summarize_trivy(report: dict) -> dict:
    if isinstance(report, dict) and report.get("status") in {"missing", "invalid"}:
        return {
            "tool": "trivy",
            "status": report["status"],
            "count": 0,
            "details": report,
            "sample": [],
        }
    results = report.get("Results", []) if isinstance(report, dict) else []
    vulnerabilities = []
    severity = {"LOW": 0, "MEDIUM": 0, "HIGH": 0, "CRITICAL": 0}
    for result in results:
        for vuln in result.get("Vulnerabilities", []) or []:
            vulnerabilities.append(vuln)
            sev = vuln.get("Severity", "LOW")
            severity[sev] = severity.get(sev, 0) + 1
    return {
        "tool": "trivy",
        "status": "ok" if not vulnerabilities else "findings",
        "count": len(vulnerabilities),
        "severity": severity,
        "sample": vulnerabilities[:5],
    }


def write_html(summary: dict, destination: Path) -> None:
    rows = []
    for result in summary["results"]:
        detail = escape(json.dumps(result, indent=2))
        rows.append(
            "<tr>"
            f"<td>{escape(result['tool'])}</td>"
            f"<td>{escape(result['status'])}</td>"
            f"<td>{result['count']}</td>"
            f"<td><pre>{detail}</pre></td>"
            "</tr>"
        )

    html = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>SecureMLOps Security Report</title>
  <style>
    body {{ font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 2rem; color: #16202a; }}
    h1 {{ margin-bottom: 0.25rem; }}
    p {{ color: #4a5565; }}
    table {{ border-collapse: collapse; width: 100%; margin-top: 1.5rem; }}
    th, td {{ border: 1px solid #d8dee6; padding: 0.75rem; vertical-align: top; text-align: left; }}
    th {{ background: #f6f8fa; }}
    pre {{ margin: 0; white-space: pre-wrap; word-break: break-word; }}
  </style>
</head>
<body>
  <h1>SecureMLOps Security Report</h1>
  <p>Generated at {escape(summary['generated_at'])}</p>
  <table>
    <thead>
      <tr><th>Tool</th><th>Status</th><th>Count</th><th>Details</th></tr>
    </thead>
    <tbody>
      {''.join(rows)}
    </tbody>
  </table>
</body>
</html>
"""
    destination.write_text(html)


def main() -> None:
    REPORT_DIR.mkdir(parents=True, exist_ok=True)

    gitleaks = summarize_gitleaks(load_json(REPORT_DIR / "gitleaks-report.json"))
    bandit = summarize_bandit(load_json(REPORT_DIR / "bandit-report.json"))
    trivy = summarize_trivy(load_json(REPORT_DIR / "trivy-report.json"))

    summary = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "results": [gitleaks, bandit, trivy],
    }

    json_path = REPORT_DIR / "security-summary.json"
    html_path = REPORT_DIR / "security-summary.html"
    json_path.write_text(json.dumps(summary, indent=2))
    write_html(summary, html_path)

    print(f"Wrote {json_path.relative_to(ROOT)}")
    print(f"Wrote {html_path.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
