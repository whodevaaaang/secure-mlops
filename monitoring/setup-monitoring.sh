#!/bin/bash
# Setup Prometheus + Grafana monitoring stack on Minikube
# Usage: cd monitoring && bash setup-monitoring.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=== SecureMLOps Monitoring Setup ==="

# Step 1: Add Helm repo
echo "[1/6] Adding prometheus-community Helm repo..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo update

# Step 2: Install kube-prometheus-stack (includes Pushgateway for drift metrics)
echo "[2/6] Installing kube-prometheus-stack..."
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  -f "$SCRIPT_DIR/prometheus/kube-prometheus-values.yml" \
  --wait --timeout 5m

# Step 3: Create dashboard ConfigMaps from JSON files
echo "[3/6] Loading Grafana dashboards..."
for dashboard in "$SCRIPT_DIR/grafana/dashboards/"*.json; do
  name=$(basename "$dashboard" .json)
  kubectl create configmap "grafana-dashboard-${name}" \
    --from-file="${name}.json=${dashboard}" \
    --dry-run=client -o yaml | \
    kubectl label --local -f - grafana_dashboard=1 -o yaml --dry-run=client | \
    kubectl apply -f -
done

# Step 4: Apply ServiceMonitor for ML API
echo "[4/6] Applying ServiceMonitor..."
kubectl apply -f "$SCRIPT_DIR/prometheus/servicemonitor.yml"

# Step 5: Build drift detector image in Minikube
echo "[5/6] Building drift detector image..."
eval $(minikube docker-env)
docker build -t securemlops-drift-detector:v1 "$SCRIPT_DIR/evidently/"

# Step 6: Display access info
echo "[6/6] Setup complete!"
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
echo ""
echo "Drift detection CronJob will run on the schedule defined in Helm values."
echo "To run drift detection manually:"
echo "  kubectl create job --from=cronjob/securemlops-drift-detection drift-manual-\$(date +%s)"
