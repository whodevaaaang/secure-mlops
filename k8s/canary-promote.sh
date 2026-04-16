#!/bin/bash
# SecureMLOps Canary Promotion Script
# Monitors canary health and either promotes to stable or rolls back.
#
# Usage:
#   bash k8s/canary-promote.sh                     # Analyze and prompt for promotion
#   bash k8s/canary-promote.sh --auto              # Auto-promote if healthy
#   bash k8s/canary-promote.sh --rollback          # Rollback canary immediately
#   bash k8s/canary-promote.sh --status            # Show canary vs stable metrics

set -euo pipefail

RELEASE_NAME="${HELM_RELEASE:-securemlops}"
NAMESPACE="${K8S_NAMESPACE:-default}"
HELM_CHART="${HELM_CHART_PATH:-k8s/helm-chart/securemlops}"
PROM_URL="${PROMETHEUS_URL:-http://localhost:9090}"
ERROR_THRESHOLD="${CANARY_ERROR_THRESHOLD:-0.05}"
LATENCY_THRESHOLD="${CANARY_LATENCY_THRESHOLD:-500}"
CHECK_INTERVAL="${CANARY_CHECK_INTERVAL:-30}"
CHECK_COUNT="${CANARY_CHECK_COUNT:-10}"

usage() {
    echo "SecureMLOps Canary Promotion"
    echo ""
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  (no args)     Analyze canary health and prompt for promotion"
    echo "  --auto        Auto-promote if canary passes all checks"
    echo "  --rollback    Remove canary and keep stable"
    echo "  --status      Show current canary vs stable metrics"
    echo "  --help        Show this help"
}

show_status() {
    echo "=== Canary Deployment Status ==="
    echo ""
    echo "--- Stable Deployment ---"
    kubectl get deployment "${RELEASE_NAME}-stable" --namespace "${NAMESPACE}" -o wide 2>/dev/null || echo "  Not deployed"
    echo ""
    echo "--- Canary Deployment ---"
    kubectl get deployment "${RELEASE_NAME}-canary" --namespace "${NAMESPACE}" -o wide 2>/dev/null || echo "  Not deployed"
    echo ""
    echo "--- All Pods ---"
    kubectl get pods -l "app=${RELEASE_NAME}-api" --namespace "${NAMESPACE}" -o wide --show-labels
    echo ""

    # Calculate traffic split
    local stable_replicas canary_replicas
    stable_replicas=$(kubectl get deployment "${RELEASE_NAME}-stable" --namespace "${NAMESPACE}" \
        -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    canary_replicas=$(kubectl get deployment "${RELEASE_NAME}-canary" --namespace "${NAMESPACE}" \
        -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    local total=$((stable_replicas + canary_replicas))

    if [ "$total" -gt 0 ]; then
        local canary_pct=$((canary_replicas * 100 / total))
        echo "Traffic split: stable=${stable_replicas} ($(( 100 - canary_pct ))%) | canary=${canary_replicas} (${canary_pct}%)"
    fi
}

check_canary_health() {
    echo "Checking canary deployment health..."

    # Verify canary pods are ready
    local ready
    ready=$(kubectl get deployment "${RELEASE_NAME}-canary" --namespace "${NAMESPACE}" \
        -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    local desired
    desired=$(kubectl get deployment "${RELEASE_NAME}-canary" --namespace "${NAMESPACE}" \
        -o jsonpath='{.spec.replicas}')

    if [ "${ready}" != "${desired}" ]; then
        echo "FAIL: Canary pods not ready (${ready}/${desired})"
        return 1
    fi
    echo "PASS: All canary pods ready (${ready}/${desired})"

    # Check canary restarts
    local restarts
    restarts=$(kubectl get pods -l "app=${RELEASE_NAME}-api,track=canary" --namespace "${NAMESPACE}" \
        -o jsonpath='{.items[*].status.containerStatuses[*].restartCount}' 2>/dev/null | \
        awk '{s=0; for(i=1;i<=NF;i++) s+=$i; print s}')
    if [ "${restarts:-0}" -gt 0 ]; then
        echo "WARN: Canary has ${restarts} restart(s)"
    else
        echo "PASS: No canary restarts"
    fi

    # Test canary endpoint directly
    local canary_port
    canary_port=$(kubectl get service "${RELEASE_NAME}-canary" --namespace "${NAMESPACE}" \
        -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")

    if [ -n "$canary_port" ]; then
        local node_ip
        node_ip=$(minikube ip 2>/dev/null || echo "localhost")
        local health_status
        health_status=$(curl -sf -o /dev/null -w "%{http_code}" \
            "http://${node_ip}:${canary_port}/health" 2>/dev/null || echo "000")

        if [ "$health_status" = "200" ]; then
            echo "PASS: Canary health endpoint returned 200"
        else
            echo "FAIL: Canary health endpoint returned ${health_status}"
            return 1
        fi
    fi

    return 0
}

promote_canary() {
    local canary_image canary_tag
    canary_image=$(kubectl get deployment "${RELEASE_NAME}-canary" --namespace "${NAMESPACE}" \
        -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
    canary_tag="${canary_image##*:}"

    echo ""
    echo "=== Promoting Canary ==="
    echo "Canary image: ${canary_image}"
    echo "Promoting canary to stable..."
    echo ""

    # Disable canary mode and update the main deployment to the canary image
    helm upgrade "${RELEASE_NAME}" "${HELM_CHART}" \
        --namespace "${NAMESPACE}" \
        --set canary.enabled=false \
        --set image.tag="${canary_tag}" \
        --reuse-values \
        --wait --timeout 5m

    echo ""
    echo "=== Promotion Complete ==="
    echo "Stable deployment now running: ${canary_image}"
}

rollback_canary() {
    echo "=== Rolling Back Canary ==="
    echo "Removing canary deployment..."

    helm upgrade "${RELEASE_NAME}" "${HELM_CHART}" \
        --namespace "${NAMESPACE}" \
        --set canary.enabled=false \
        --reuse-values \
        --wait --timeout 3m

    echo ""
    echo "=== Rollback Complete ==="
    echo "Canary removed. Stable deployment unchanged."
}

auto_promote() {
    echo "=== Canary Auto-Promotion Analysis ==="
    echo "Running ${CHECK_COUNT} checks at ${CHECK_INTERVAL}s intervals"
    echo "Error threshold: ${ERROR_THRESHOLD} | Latency threshold: ${LATENCY_THRESHOLD}ms"
    echo ""

    local passed=0
    local failed=0

    for i in $(seq 1 "$CHECK_COUNT"); do
        echo "--- Check ${i}/${CHECK_COUNT} ---"
        if check_canary_health; then
            passed=$((passed + 1))
            echo "Result: PASS (${passed}/${i})"
        else
            failed=$((failed + 1))
            echo "Result: FAIL (${failed} failures)"
            if [ "$failed" -ge 3 ]; then
                echo ""
                echo "Too many failures (${failed}). Auto-rolling back canary."
                rollback_canary
                exit 1
            fi
        fi

        if [ "$i" -lt "$CHECK_COUNT" ]; then
            echo "Waiting ${CHECK_INTERVAL}s..."
            sleep "$CHECK_INTERVAL"
        fi
    done

    echo ""
    echo "Analysis complete: ${passed}/${CHECK_COUNT} checks passed."

    if [ "$failed" -eq 0 ]; then
        echo "All checks passed. Promoting canary to stable."
        promote_canary
    else
        echo "Some checks failed (${failed}). Rolling back."
        rollback_canary
        exit 1
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
    --rollback)
        rollback_canary
        ;;
    --auto)
        auto_promote
        ;;
    "")
        show_status
        echo ""
        if check_canary_health; then
            echo ""
            read -rp "Canary looks healthy. Promote to stable? (y/N) " answer
            if [[ "${answer}" == "y" || "${answer}" == "Y" ]]; then
                promote_canary
            else
                echo "Aborted. Canary remains active."
            fi
        else
            echo ""
            read -rp "Canary has issues. Roll back? (y/N) " answer
            if [[ "${answer}" == "y" || "${answer}" == "Y" ]]; then
                rollback_canary
            fi
        fi
        ;;
    *)
        echo "Unknown command: $1"
        usage
        exit 1
        ;;
esac
