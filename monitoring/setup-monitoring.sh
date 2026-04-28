#!/bin/bash
# Setup Prometheus + Grafana monitoring stack on Minikube
# Includes security scanning integration (Trivy + OPA)
# Usage: cd monitoring && bash setup-monitoring.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=== SecureMLOps Monitoring Setup ==="

# Step 1: Add Helm repo
echo "[1/10] Adding prometheus-community Helm repo..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo update

# Step 2: Install kube-prometheus-stack (includes Pushgateway for drift metrics)
echo "[2/10] Installing kube-prometheus-stack..."
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  -f "$SCRIPT_DIR/prometheus/kube-prometheus-values.yml" \
  --wait --timeout 5m

# Step 3: Create dashboard ConfigMaps from JSON files
echo "[3/10] Loading Grafana dashboards..."
for dashboard in "$SCRIPT_DIR/grafana/dashboards/"*.json; do
  name=$(basename "$dashboard" .json)
  kubectl create configmap "grafana-dashboard-${name}" \
    --from-file="${name}.json=${dashboard}" \
    --dry-run=client -o yaml | \
    kubectl label --local -f - grafana_dashboard=1 -o yaml --dry-run=client | \
    kubectl apply -f -
done

# Step 4: Apply ServiceMonitor for ML API
echo "[4/10] Applying ServiceMonitor..."
kubectl apply -f "$SCRIPT_DIR/prometheus/servicemonitor.yml"

# Step 5: Build drift detector image in Minikube
echo "[5/10] Building drift detector image..."
eval $(minikube docker-env)
docker build -t securemlops-drift-detector:v1 "$SCRIPT_DIR/evidently/"

# Step 6: Run Trivy security scan (if trivy is installed)
echo "[6/10] Running security scans..."
if command -v trivy &> /dev/null; then
    echo "  Running Trivy image scan..."
    bash "$PROJECT_ROOT/security/trivy-scan.sh" "secure-mlops-api:v1" || {
        echo "  WARNING: Trivy scan found vulnerabilities (see report for details)"
    }
else
    echo "  Trivy not installed - skipping image scan"
    echo "  Install: curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin"
fi

# Step 7: Run OPA policy validation (if conftest is installed)
echo "[7/10] Validating K8s manifests against OPA policies..."
if command -v conftest &> /dev/null; then
    bash "$PROJECT_ROOT/security/validate-manifests.sh" || {
        echo "  WARNING: OPA policy violations found (see report for details)"
    }
else
    echo "  conftest not installed - skipping OPA validation"
    echo "  Install: brew install conftest  OR  go install github.com/open-policy-agent/conftest@latest"
fi

# Step 8: Verify alerting rules, RBAC, and network policies
echo "[8/10] Verifying alerting rules..."
ALERT_COUNT=$(kubectl get prometheusrules -l app=securemlops-api -o name 2>/dev/null | wc -l)
if [ "$ALERT_COUNT" -gt 0 ]; then
    echo "  Alerting rules active: ${ALERT_COUNT} PrometheusRule(s)"
else
    echo "  No alerting rules found — they will be created with the next Helm deploy"
fi

echo "[9/10] Verifying RBAC and service accounts..."
SA_COUNT=$(kubectl get serviceaccounts -l project=secure-mlops -o name 2>/dev/null | wc -l)
echo "  Service accounts: ${SA_COUNT}"
ROLE_COUNT=$(kubectl get roles -l project=secure-mlops -o name 2>/dev/null | wc -l)
echo "  Roles: ${ROLE_COUNT}"

# Step 10: Export security metrics to Pushgateway
echo "[10/10] Exporting security metrics..."
PUSHGATEWAY_URL=$(kubectl get svc monitoring-kube-prometheus-pushgateway -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
if [ -n "$PUSHGATEWAY_URL" ]; then
    bash "$PROJECT_ROOT/security/security-metrics-exporter.sh" "http://${PUSHGATEWAY_URL}:9091" || {
        echo "  WARNING: Could not export security metrics to Pushgateway"
    }
else
    echo "  Pushgateway not ready - security metrics will be exported on next scan"
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "=== Access Information ==="
GRAFANA_URL=$(minikube service monitoring-grafana --url 2>/dev/null || echo "pending")
PROMETHEUS_URL=$(minikube service monitoring-kube-prometheus-prometheus --url 2>/dev/null || echo "pending")

echo "Grafana:    $GRAFANA_URL"
echo "  Username: admin"
echo "  Password: securemlops"
echo ""
echo "Prometheus: $PROMETHEUS_URL"
echo ""
echo "Or use port-forwarding:"
echo "  kubectl port-forward svc/monitoring-grafana 3000:80"
echo "  kubectl port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090"
echo ""
echo "Dashboards loaded:"
echo "  - API Performance"
echo "  - System Resources"
echo "  - Prediction Metrics"
echo "  - Drift Detection"
echo "  - Security Scanning"
echo ""
echo "Security tools:"
echo "  - Trivy scan:       bash security/trivy-scan.sh [image:tag]"
echo "  - OPA validation:   bash security/validate-manifests.sh"
echo "  - Export metrics:    bash security/security-metrics-exporter.sh [pushgateway_url]"
echo ""
echo "Drift detection CronJob will run on the schedule defined in Helm values."
echo "To run drift detection manually:"
echo "  kubectl create job --from=cronjob/securemlops-drift-detection drift-manual-\$(date +%s)"
