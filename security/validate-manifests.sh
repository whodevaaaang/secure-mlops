#!/bin/bash
# OPA policy validation for Kubernetes manifests
# Validates Helm-rendered templates and raw manifests against security policies
# Usage: bash security/validate-manifests.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
POLICIES_DIR="$SCRIPT_DIR/opa-policies"
REPORT_DIR="$SCRIPT_DIR/reports"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
FAILURES=0
WARNINGS=0

mkdir -p "$REPORT_DIR"

echo "=== SecureMLOps OPA Policy Validation ==="
echo "Policies: $POLICIES_DIR"
echo ""

# Check if OPA/conftest is installed
if ! command -v conftest &> /dev/null; then
    echo "ERROR: conftest is not installed."
    echo "Install: brew install conftest  OR  go install github.com/open-policy-agent/conftest@latest"
    echo "Or download from: https://github.com/open-policy-agent/conftest/releases"
    exit 1
fi

# Step 1: Validate raw K8s manifests
echo "[1/3] Validating raw Kubernetes manifests..."
if [ -d "$PROJECT_ROOT/k8s/manifests" ]; then
    for manifest in "$PROJECT_ROOT/k8s/manifests/"*.yaml; do
        echo "  Checking: $(basename "$manifest")"
        if ! conftest test "$manifest" --policy "$POLICIES_DIR" --no-color 2>&1 | tee -a "$REPORT_DIR/opa-validation-${TIMESTAMP}.txt"; then
            FAILURES=$((FAILURES + 1))
        fi
    done
fi

# Step 2: Validate Helm-rendered templates
echo ""
echo "[2/3] Validating Helm-rendered templates..."
HELM_CHART="$PROJECT_ROOT/k8s/helm-chart/securemlops"
if [ -d "$HELM_CHART" ]; then
    RENDERED_DIR=$(mktemp -d)
    helm template securemlops "$HELM_CHART" --output-dir "$RENDERED_DIR" 2>/dev/null

    for rendered in $(find "$RENDERED_DIR" -name "*.yaml" -type f); do
        echo "  Checking: $(basename "$rendered")"
        RESULT=$(conftest test "$rendered" --policy "$POLICIES_DIR" --no-color 2>&1) || true
        echo "$RESULT" | tee -a "$REPORT_DIR/opa-validation-${TIMESTAMP}.txt"

        if echo "$RESULT" | grep -q "FAIL"; then
            FAILURES=$((FAILURES + 1))
        fi
        if echo "$RESULT" | grep -q "WARN"; then
            WARNINGS=$((WARNINGS + 1))
        fi
    done

    rm -rf "$RENDERED_DIR"
fi

# Step 3: Summary
echo ""
echo "[3/3] Validation Summary"
echo "========================"
echo "  Failures: $FAILURES"
echo "  Warnings: $WARNINGS"
echo "  Report:   $REPORT_DIR/opa-validation-${TIMESTAMP}.txt"

if [ "$FAILURES" -gt 0 ]; then
    echo ""
    echo "POLICY VALIDATION FAILED: $FAILURES policy violation(s) found."
    echo "Fix the violations before deploying."
    exit 1
fi

if [ "$WARNINGS" -gt 0 ]; then
    echo ""
    echo "POLICY VALIDATION PASSED with $WARNINGS warning(s)."
    exit 0
fi

echo ""
echo "POLICY VALIDATION PASSED: All manifests comply with security policies."
exit 0
