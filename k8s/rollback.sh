#!/bin/bash
# SecureMLOps Rollback Script
# Rolls back the Helm release to a previous revision with health verification.
#
# Usage:
#   bash k8s/rollback.sh                    # Roll back to previous revision
#   bash k8s/rollback.sh 3                  # Roll back to specific revision
#   bash k8s/rollback.sh --list             # List available revisions
#   bash k8s/rollback.sh --status           # Show current deployment status

set -euo pipefail

RELEASE_NAME="${HELM_RELEASE:-securemlops}"
NAMESPACE="${K8S_NAMESPACE:-default}"
TIMEOUT="120s"

usage() {
    echo "Usage: $0 [REVISION|--list|--status]"
    echo ""
    echo "Options:"
    echo "  (no args)   Roll back to the previous revision"
    echo "  REVISION    Roll back to a specific revision number"
    echo "  --list      List all available revisions"
    echo "  --status    Show current deployment status"
    echo "  --help      Show this help"
}

list_revisions() {
    echo "=== Helm Release History: ${RELEASE_NAME} ==="
    helm history "${RELEASE_NAME}" --namespace "${NAMESPACE}" --max 10
}

show_status() {
    echo "=== Current Deployment Status ==="
    echo ""
    echo "--- Helm Release ---"
    helm status "${RELEASE_NAME}" --namespace "${NAMESPACE}" --show-desc 2>/dev/null || echo "Release not found"
    echo ""
    echo "--- Pods ---"
    kubectl get pods -l "app=${RELEASE_NAME}-api" --namespace "${NAMESPACE}" -o wide
    echo ""
    echo "--- Deployment ---"
    kubectl get deployment "${RELEASE_NAME}-api" --namespace "${NAMESPACE}" -o wide
    echo ""
    echo "--- ReplicaSets (revision history) ---"
    kubectl get replicasets -l "app=${RELEASE_NAME}-api" --namespace "${NAMESPACE}" --sort-by='.metadata.creationTimestamp'
}

verify_health() {
    echo ""
    echo "--- Verifying deployment health ---"

    echo "Waiting for rollout to complete..."
    if ! kubectl rollout status "deployment/${RELEASE_NAME}-api" \
        --namespace "${NAMESPACE}" --timeout="${TIMEOUT}"; then
        echo "ERROR: Rollout did not complete within ${TIMEOUT}"
        return 1
    fi

    echo "Checking pod readiness..."
    local ready
    ready=$(kubectl get deployment "${RELEASE_NAME}-api" --namespace "${NAMESPACE}" \
        -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    local desired
    desired=$(kubectl get deployment "${RELEASE_NAME}-api" --namespace "${NAMESPACE}" \
        -o jsonpath='{.spec.replicas}')

    if [ "${ready}" = "${desired}" ]; then
        echo "All ${ready}/${desired} replicas are ready."
        return 0
    else
        echo "WARNING: Only ${ready}/${desired} replicas are ready."
        return 1
    fi
}

rollback() {
    local revision="${1:-}"

    echo "=== SecureMLOps Rollback ==="
    echo "Release: ${RELEASE_NAME}"
    echo "Namespace: ${NAMESPACE}"

    # Show current state
    local current_revision
    current_revision=$(helm history "${RELEASE_NAME}" --namespace "${NAMESPACE}" \
        --max 1 -o json | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['revision'])" 2>/dev/null || echo "unknown")
    echo "Current revision: ${current_revision}"

    if [ -n "${revision}" ]; then
        echo "Target revision: ${revision}"
        echo ""
        echo "Rolling back to revision ${revision}..."
        helm rollback "${RELEASE_NAME}" "${revision}" \
            --namespace "${NAMESPACE}" \
            --wait --timeout 3m
    else
        echo "Target: previous revision"
        echo ""
        echo "Rolling back to previous revision..."
        helm rollback "${RELEASE_NAME}" \
            --namespace "${NAMESPACE}" \
            --wait --timeout 3m
    fi

    echo ""
    echo "Rollback command completed."
    verify_health

    echo ""
    local new_revision
    new_revision=$(helm history "${RELEASE_NAME}" --namespace "${NAMESPACE}" \
        --max 1 -o json | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['revision'])" 2>/dev/null || echo "unknown")
    echo "=== Rollback Complete ==="
    echo "Previous revision: ${current_revision}"
    echo "Current revision:  ${new_revision}"
}

# Main
case "${1:-}" in
    --help|-h)
        usage
        ;;
    --list)
        list_revisions
        ;;
    --status)
        show_status
        ;;
    *)
        rollback "${1:-}"
        ;;
esac
