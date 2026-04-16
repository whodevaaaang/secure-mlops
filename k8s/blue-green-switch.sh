#!/bin/bash
# SecureMLOps Blue-Green Deployment Switch
# Switches live traffic between blue and green slots with health verification.
#
# Usage:
#   bash k8s/blue-green-switch.sh                # Switch to the inactive slot
#   bash k8s/blue-green-switch.sh blue            # Switch to blue
#   bash k8s/blue-green-switch.sh green           # Switch to green
#   bash k8s/blue-green-switch.sh --status        # Show current slot status
#   bash k8s/blue-green-switch.sh --deploy <tag>  # Deploy new image to inactive slot

set -euo pipefail

RELEASE_NAME="${HELM_RELEASE:-securemlops}"
NAMESPACE="${K8S_NAMESPACE:-default}"
HELM_CHART="${HELM_CHART_PATH:-k8s/helm-chart/securemlops}"
TIMEOUT="120s"

usage() {
    echo "SecureMLOps Blue-Green Deployment Switch"
    echo ""
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  (no args)         Switch live traffic to the inactive slot"
    echo "  blue|green        Switch live traffic to the specified slot"
    echo "  --status          Show which slot is active and pod status"
    echo "  --deploy <tag>    Deploy a new image tag to the inactive slot"
    echo "  --help            Show this help"
}

get_active_slot() {
    kubectl get service "${RELEASE_NAME}-service" \
        --namespace "${NAMESPACE}" \
        -o jsonpath='{.spec.selector.slot}' 2>/dev/null || echo "unknown"
}

get_inactive_slot() {
    local active
    active=$(get_active_slot)
    if [ "$active" = "blue" ]; then
        echo "green"
    else
        echo "blue"
    fi
}

show_status() {
    local active
    active=$(get_active_slot)
    local inactive
    inactive=$(get_inactive_slot)

    echo "=== Blue-Green Deployment Status ==="
    echo ""
    echo "Active slot (live traffic): ${active}"
    echo "Inactive slot (standby):    ${inactive}"
    echo ""

    echo "--- Blue Deployment ---"
    kubectl get deployment "${RELEASE_NAME}-blue" --namespace "${NAMESPACE}" -o wide 2>/dev/null || echo "  Not deployed"
    echo ""

    echo "--- Green Deployment ---"
    kubectl get deployment "${RELEASE_NAME}-green" --namespace "${NAMESPACE}" -o wide 2>/dev/null || echo "  Not deployed"
    echo ""

    echo "--- Pods ---"
    kubectl get pods -l "app=${RELEASE_NAME}-api" --namespace "${NAMESPACE}" -o wide --show-labels
    echo ""

    echo "--- Services ---"
    kubectl get service "${RELEASE_NAME}-service" "${RELEASE_NAME}-preview" \
        --namespace "${NAMESPACE}" -o wide 2>/dev/null || true
}

verify_slot_health() {
    local slot="$1"
    echo "Verifying ${slot} deployment health..."

    # Wait for rollout
    if ! kubectl rollout status "deployment/${RELEASE_NAME}-${slot}" \
        --namespace "${NAMESPACE}" --timeout="${TIMEOUT}"; then
        echo "ERROR: ${slot} deployment rollout did not complete"
        return 1
    fi

    # Check readiness
    local ready
    ready=$(kubectl get deployment "${RELEASE_NAME}-${slot}" --namespace "${NAMESPACE}" \
        -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    local desired
    desired=$(kubectl get deployment "${RELEASE_NAME}-${slot}" --namespace "${NAMESPACE}" \
        -o jsonpath='{.spec.replicas}')

    if [ "${ready}" != "${desired}" ]; then
        echo "ERROR: Only ${ready}/${desired} replicas ready in ${slot}"
        return 1
    fi

    echo "All ${ready}/${desired} ${slot} replicas are ready."
    return 0
}

switch_traffic() {
    local target_slot="$1"
    local active
    active=$(get_active_slot)

    if [ "$target_slot" = "$active" ]; then
        echo "Slot '${target_slot}' is already active. Nothing to do."
        exit 0
    fi

    echo "=== Blue-Green Switch ==="
    echo "Current active: ${active}"
    echo "Switching to:   ${target_slot}"
    echo ""

    # Verify target is healthy before switching
    if ! verify_slot_health "$target_slot"; then
        echo ""
        echo "ABORT: Target slot '${target_slot}' is not healthy. Traffic NOT switched."
        exit 1
    fi

    echo ""
    echo "Switching live traffic to ${target_slot}..."

    # Update Helm release to point service to new slot
    helm upgrade "${RELEASE_NAME}" "${HELM_CHART}" \
        --namespace "${NAMESPACE}" \
        --set blueGreen.activeSlot="${target_slot}" \
        --reuse-values \
        --wait --timeout 2m

    echo ""
    echo "=== Switch Complete ==="
    echo "Live traffic now served by: ${target_slot}"
    echo "Preview/standby slot:       ${active}"
    echo ""
    echo "Preview the old slot at NodePort $(kubectl get service "${RELEASE_NAME}-preview" \
        --namespace "${NAMESPACE}" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo 'N/A')"
}

deploy_to_inactive() {
    local new_tag="$1"
    local inactive
    inactive=$(get_inactive_slot)

    echo "=== Deploying to inactive slot: ${inactive} ==="
    echo "New image tag: ${new_tag}"
    echo ""

    helm upgrade "${RELEASE_NAME}" "${HELM_CHART}" \
        --namespace "${NAMESPACE}" \
        --set "blueGreen.${inactive}.image.tag=${new_tag}" \
        --reuse-values \
        --wait --timeout 5m

    echo ""
    if verify_slot_health "$inactive"; then
        echo ""
        echo "Deployment to ${inactive} successful."
        echo "Test the new version via the preview service before switching:"
        echo "  kubectl port-forward service/${RELEASE_NAME}-preview 8081:80"
        echo ""
        echo "When ready, switch traffic:"
        echo "  bash k8s/blue-green-switch.sh ${inactive}"
    else
        echo ""
        echo "WARNING: Deployment completed but health check failed."
        echo "Investigate before switching traffic."
    fi
}

# Main
case "${1:-}" in
    --help|-h)
        usage
        ;;
    --status)
        show_status
        ;;
    --deploy)
        if [ -z "${2:-}" ]; then
            echo "ERROR: --deploy requires an image tag argument"
            echo "Usage: $0 --deploy <tag>"
            exit 1
        fi
        deploy_to_inactive "$2"
        ;;
    blue|green)
        switch_traffic "$1"
        ;;
    "")
        target=$(get_inactive_slot)
        switch_traffic "$target"
        ;;
    *)
        echo "Unknown command: $1"
        usage
        exit 1
        ;;
esac
