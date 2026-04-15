#!/bin/bash
# Export Trivy and OPA scan results as Prometheus metrics via Pushgateway
# Called after security scans to feed the Grafana security dashboard
# Usage: bash security/security-metrics-exporter.sh [pushgateway_url]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT_DIR="$SCRIPT_DIR/reports"
PUSHGATEWAY_URL="${1:-http://localhost:9091}"

echo "=== Exporting Security Metrics to Pushgateway ==="
echo "Pushgateway: $PUSHGATEWAY_URL"

# Find latest Trivy JSON report
LATEST_REPORT=$(ls -t "$REPORT_DIR"/vuln-report-*.json 2>/dev/null | head -1)

CRITICAL=0
HIGH=0
MEDIUM=0

if [ -n "$LATEST_REPORT" ] && command -v jq &>/dev/null; then
    echo "Parsing: $LATEST_REPORT"
    CRITICAL=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="CRITICAL")] | length' "$LATEST_REPORT" 2>/dev/null || echo 0)
    HIGH=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="HIGH")] | length' "$LATEST_REPORT" 2>/dev/null || echo 0)
    MEDIUM=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="MEDIUM")] | length' "$LATEST_REPORT" 2>/dev/null || echo 0)
fi

TIMESTAMP=$(date +%s)

# Find latest OPA validation report
LATEST_OPA=$(ls -t "$REPORT_DIR"/opa-validation-*.txt 2>/dev/null | head -1)

OPA_VIOLATIONS=0
OPA_WARNINGS=0

if [ -n "$LATEST_OPA" ]; then
    echo "Parsing: $LATEST_OPA"
    OPA_VIOLATIONS=$(grep -c "FAIL" "$LATEST_OPA" 2>/dev/null || echo 0)
    OPA_WARNINGS=$(grep -c "WARN" "$LATEST_OPA" 2>/dev/null || echo 0)
fi

# Push metrics to Pushgateway
cat <<METRICS_EOF | curl --silent --data-binary @- "$PUSHGATEWAY_URL/metrics/job/security_scan"
# HELP trivy_scan_critical_count Number of CRITICAL vulnerabilities found
# TYPE trivy_scan_critical_count gauge
trivy_scan_critical_count $CRITICAL
# HELP trivy_scan_high_count Number of HIGH vulnerabilities found
# TYPE trivy_scan_high_count gauge
trivy_scan_high_count $HIGH
# HELP trivy_scan_medium_count Number of MEDIUM vulnerabilities found
# TYPE trivy_scan_medium_count gauge
trivy_scan_medium_count $MEDIUM
# HELP trivy_scan_last_run_timestamp Timestamp of last Trivy scan
# TYPE trivy_scan_last_run_timestamp gauge
trivy_scan_last_run_timestamp $TIMESTAMP
# HELP opa_policy_violations_total Number of OPA policy violations
# TYPE opa_policy_violations_total gauge
opa_policy_violations_total $OPA_VIOLATIONS
# HELP opa_policy_warnings_total Number of OPA policy warnings
# TYPE opa_policy_warnings_total gauge
opa_policy_warnings_total $OPA_WARNINGS
METRICS_EOF

echo ""
echo "Metrics exported:"
echo "  trivy_scan_critical_count: $CRITICAL"
echo "  trivy_scan_high_count: $HIGH"
echo "  trivy_scan_medium_count: $MEDIUM"
echo "  trivy_scan_last_run_timestamp: $TIMESTAMP"
echo "  opa_policy_violations_total: $OPA_VIOLATIONS"
echo "  opa_policy_warnings_total: $OPA_WARNINGS"
echo ""
echo "View in Grafana Security Scanning dashboard."
