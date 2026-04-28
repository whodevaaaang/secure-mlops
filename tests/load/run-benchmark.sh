#!/bin/bash
# SecureMLOps Load Testing Benchmark
# Runs a standardized set of load tests and generates reports.
#
# Usage:
#   bash tests/load/run-benchmark.sh                          # Default: 50 users, 60s
#   bash tests/load/run-benchmark.sh --users 100 --duration 120
#   bash tests/load/run-benchmark.sh --host http://192.168.49.2:30080

set -euo pipefail

# Defaults
HOST="${HOST:-http://localhost:8080}"
USERS=50
SPAWN_RATE=5
DURATION=60
RESULTS_DIR="tests/load/results"

usage() {
    echo "SecureMLOps Load Testing Benchmark"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --host URL        Target host (default: http://localhost:8080)"
    echo "  --users N         Number of concurrent users (default: 50)"
    echo "  --spawn-rate N    Users spawned per second (default: 5)"
    echo "  --duration N      Test duration in seconds (default: 60)"
    echo "  --help            Show this help"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --host) HOST="$2"; shift 2 ;;
        --users) USERS="$2"; shift 2 ;;
        --spawn-rate) SPAWN_RATE="$2"; shift 2 ;;
        --duration) DURATION="$2"; shift 2 ;;
        --help|-h) usage; exit 0 ;;
        *) echo "Unknown option: $1"; usage; exit 1 ;;
    esac
done

echo "=============================================="
echo "  SecureMLOps Load Test Benchmark"
echo "=============================================="
echo "Host:        ${HOST}"
echo "Users:       ${USERS}"
echo "Spawn rate:  ${SPAWN_RATE}/sec"
echo "Duration:    ${DURATION}s"
echo "Results:     ${RESULTS_DIR}/"
echo "=============================================="
echo ""

# Check prerequisites
if ! command -v locust &>/dev/null; then
    echo "ERROR: locust not found. Install with: pip install -r tests/load/requirements.txt"
    exit 1
fi

# Verify target is reachable
echo "Checking target availability..."
if ! curl -sf "${HOST}/health" > /dev/null 2>&1; then
    echo "WARNING: ${HOST}/health is not reachable."
    echo "Make sure the API is running and accessible."
    echo ""
    echo "Quick start options:"
    echo "  kubectl port-forward service/securemlops-service 8080:80"
    echo "  docker-compose up -d"
    echo ""
    read -rp "Continue anyway? (y/N) " answer
    if [[ "${answer}" != "y" && "${answer}" != "Y" ]]; then
        exit 1
    fi
fi

# Create results directory
mkdir -p "${RESULTS_DIR}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo ""
echo "Starting load test..."
echo ""

# Run the benchmark
locust \
    -f tests/load/locustfile.py \
    --host "${HOST}" \
    --headless \
    -u "${USERS}" \
    -r "${SPAWN_RATE}" \
    -t "${DURATION}s" \
    --csv="${RESULTS_DIR}/benchmark_${TIMESTAMP}" \
    --html="${RESULTS_DIR}/benchmark_${TIMESTAMP}.html" \
    --print-stats \
    --only-summary

echo ""
echo "=============================================="
echo "  Benchmark Complete"
echo "=============================================="
echo ""
echo "Reports generated:"
echo "  HTML:  ${RESULTS_DIR}/benchmark_${TIMESTAMP}.html"
echo "  CSV:   ${RESULTS_DIR}/benchmark_${TIMESTAMP}_stats.csv"
echo ""

# Print summary from CSV
if [ -f "${RESULTS_DIR}/benchmark_${TIMESTAMP}_stats.csv" ]; then
    echo "--- Summary ---"
    echo ""
    # Extract the Aggregated row
    tail -1 "${RESULTS_DIR}/benchmark_${TIMESTAMP}_stats.csv" | \
        awk -F',' '{
            printf "Total Requests:  %s\n", $3
            printf "Failures:        %s\n", $4
            printf "Avg Response:    %s ms\n", $6
            printf "p50 Response:    %s ms\n", $8
            printf "p95 Response:    %s ms\n", $12
            printf "p99 Response:    %s ms\n", $14
            printf "Requests/sec:    %s\n", $10
        }'
fi
