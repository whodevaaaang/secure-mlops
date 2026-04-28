#!/bin/bash
# SecureMLOps Model Promotion Script
# Promotes an MLflow model version through staging environments.
#
# Usage:
#   bash scripts/promote-model.sh --list                    # List model versions
#   bash scripts/promote-model.sh --stage <version>         # Promote to Staging
#   bash scripts/promote-model.sh --prod <version>          # Promote to Production
#   bash scripts/promote-model.sh --deploy                  # Deploy latest Production model

set -euo pipefail

MODEL_NAME="${MODEL_NAME:-securemlops-loan-default}"
MLFLOW_TRACKING_URI="${MLFLOW_TRACKING_URI:-http://localhost:5000}"
RELEASE_NAME="${HELM_RELEASE:-securemlops}"
NAMESPACE="${K8S_NAMESPACE:-default}"
HELM_CHART="${HELM_CHART_PATH:-k8s/helm-chart/securemlops}"

usage() {
    echo "SecureMLOps Model Promotion"
    echo ""
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  --list              List all model versions and their stages"
    echo "  --stage <version>   Transition model version to Staging"
    echo "  --prod <version>    Transition model version to Production"
    echo "  --deploy            Build and deploy the latest Production model"
    echo "  --help              Show this help"
    echo ""
    echo "Environment:"
    echo "  MLFLOW_TRACKING_URI   MLflow server URL (default: http://localhost:5000)"
    echo "  MODEL_NAME            Registered model name (default: securemlops-loan-default)"
}

list_versions() {
    echo "=== Model Versions: ${MODEL_NAME} ==="
    python3 -c "
import mlflow
mlflow.set_tracking_uri('${MLFLOW_TRACKING_URI}')
client = mlflow.tracking.MlflowClient()
try:
    versions = client.search_model_versions(\"name='${MODEL_NAME}'\")
    if not versions:
        print('No versions found.')
    else:
        print(f'{'Version':<10} {'Stage':<15} {'Status':<10} {'Run ID':<35} {'Created'}')
        print('-' * 100)
        for v in sorted(versions, key=lambda x: int(x.version), reverse=True):
            from datetime import datetime
            created = datetime.fromtimestamp(v.creation_timestamp / 1000).strftime('%Y-%m-%d %H:%M')
            print(f'{v.version:<10} {v.current_stage:<15} {v.status:<10} {v.run_id:<35} {created}')
except Exception as e:
    print(f'Error: {e}')
    print('Make sure MLflow is running at ${MLFLOW_TRACKING_URI}')
"
}

transition_stage() {
    local version="$1"
    local stage="$2"

    echo "Transitioning model version ${version} to ${stage}..."
    python3 -c "
import mlflow
mlflow.set_tracking_uri('${MLFLOW_TRACKING_URI}')
client = mlflow.tracking.MlflowClient()
client.transition_model_version_stage(
    name='${MODEL_NAME}',
    version=${version},
    stage='${stage}',
    archive_existing_versions=True,
)
print(f'Model ${MODEL_NAME} v${version} -> ${stage}')
"
}

deploy_production_model() {
    echo "=== Deploying Production Model ==="
    echo ""

    # Get the latest Production model version
    local model_uri
    model_uri=$(python3 -c "
import mlflow
mlflow.set_tracking_uri('${MLFLOW_TRACKING_URI}')
client = mlflow.tracking.MlflowClient()
versions = client.get_latest_versions('${MODEL_NAME}', stages=['Production'])
if versions:
    print(f'models:/${MODEL_NAME}/Production')
else:
    print('NONE')
")

    if [ "$model_uri" = "NONE" ]; then
        echo "ERROR: No Production model found. Promote a version first:"
        echo "  $0 --prod <version>"
        exit 1
    fi

    echo "Production model URI: ${model_uri}"
    echo ""

    # Download the model locally
    echo "Downloading model artifacts..."
    python3 -c "
import mlflow
import shutil
mlflow.set_tracking_uri('${MLFLOW_TRACKING_URI}')
model_path = mlflow.artifacts.download_artifacts('${model_uri}')
# Copy the model to the app directory
import os
dest = 'ml-app/model/artifacts/'
os.makedirs(dest, exist_ok=True)
src_model = os.path.join(model_path, 'model.pkl')
if os.path.exists(src_model):
    shutil.copy2(src_model, os.path.join(dest, 'model.joblib'))
print(f'Model downloaded to {dest}')
"

    # Rebuild and deploy
    echo ""
    echo "Rebuilding Docker image with new model..."
    local new_tag
    new_tag="v$(date +%Y%m%d%H%M%S)"

    eval "$(minikube docker-env)" && docker build -t "secure-mlops-api:${new_tag}" ml-app/

    echo "Deploying ${new_tag}..."
    helm upgrade "${RELEASE_NAME}" "${HELM_CHART}" \
        --namespace "${NAMESPACE}" \
        --set "image.tag=${new_tag}" \
        --reuse-values \
        --wait --timeout 5m

    echo ""
    echo "=== Deployment Complete ==="
    echo "Running image: secure-mlops-api:${new_tag}"
}

# Main
case "${1:-}" in
    --help|-h)
        usage
        ;;
    --list)
        list_versions
        ;;
    --stage)
        if [ -z "${2:-}" ]; then
            echo "ERROR: --stage requires a version number"
            exit 1
        fi
        transition_stage "$2" "Staging"
        ;;
    --prod)
        if [ -z "${2:-}" ]; then
            echo "ERROR: --prod requires a version number"
            exit 1
        fi
        transition_stage "$2" "Production"
        ;;
    --deploy)
        deploy_production_model
        ;;
    *)
        usage
        exit 1
        ;;
esac
