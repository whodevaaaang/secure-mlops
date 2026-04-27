#!/bin/bash
# Trivy container image vulnerability scanner
# Run before Helm deploy to catch vulnerabilities early
# Usage: bash security/trivy-scan.sh [image:tag]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
IMAGE="${1:-secure-mlops-api:v1}"
TRIVY_CONFIG="$SCRIPT_DIR/trivy-config.yaml"
REPORT_DIR="$SCRIPT_DIR/reports"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "$REPORT_DIR"

echo "=== SecureMLOps Trivy Security Scan ==="
echo "Image: $IMAGE"
echo "Config: $TRIVY_CONFIG"
echo ""

# Check if trivy is installed
if ! command -v trivy &> /dev/null; then
    echo "ERROR: Trivy is not installed."
    echo "Install: curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin"
    exit 1
fi

# Step 1: Vulnerability scan (blocks on CRITICAL/HIGH)
echo "[1/3] Scanning for vulnerabilities..."
trivy image \
    --config "$TRIVY_CONFIG" \
    --severity CRITICAL,HIGH \
    --exit-code 1 \
    --format table \
    "$IMAGE" 2>&1 | tee "$REPORT_DIR/vuln-scan-${TIMESTAMP}.txt"
VULN_EXIT=${PIPESTATUS[0]}

# Step 2: Full scan for reporting (all severities, no exit-code override)
echo ""
echo "[2/3] Generating full vulnerability report..."
trivy image \
    --config "$TRIVY_CONFIG" \
    --exit-code 0 \
    --format json \
    --output "$REPORT_DIR/vuln-report-${TIMESTAMP}.json" \
    "$IMAGE"

# Step 3: Dockerfile misconfiguration scan
echo "[3/3] Scanning Dockerfile for misconfigurations..."
if [ -f "$PROJECT_ROOT/ml-app/Dockerfile" ]; then
    trivy config \
        --severity CRITICAL,HIGH,MEDIUM \
        --exit-code 0 \
        "$PROJECT_ROOT/ml-app/Dockerfile" 2>&1 | tee "$REPORT_DIR/dockerfile-scan-${TIMESTAMP}.txt"
fi

echo ""
echo "=== Scan Reports ==="
echo "  Vulnerability: $REPORT_DIR/vuln-scan-${TIMESTAMP}.txt"
echo "  Full report:   $REPORT_DIR/vuln-report-${TIMESTAMP}.json"
echo "  Dockerfile:    $REPORT_DIR/dockerfile-scan-${TIMESTAMP}.txt"

if [ "$VULN_EXIT" -ne 0 ]; then
    echo ""
    echo "SECURITY GATE FAILED: CRITICAL/HIGH vulnerabilities found."
    echo "Fix vulnerabilities before deploying."
    exit 1
fi

echo ""
echo "SECURITY GATE PASSED: No CRITICAL/HIGH vulnerabilities found."
exit 0
