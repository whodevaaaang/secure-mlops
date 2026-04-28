# SealedSecrets for SecureMLOps

This directory contains encrypted secrets managed by [Bitnami SealedSecrets](https://github.com/bitnami-labs/sealed-secrets).

## How It Works

1. **SealedSecret controller** runs in the cluster and decrypts SealedSecret resources into regular Secrets
2. **kubeseal CLI** encrypts secrets with the controller's public key so they're safe to commit to git
3. Only the controller (with its private key) can decrypt them

## Setup

```bash
# Install the SealedSecrets controller
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm install sealed-secrets sealed-secrets/sealed-secrets --namespace kube-system

# Install the kubeseal CLI
# macOS:
brew install kubeseal
# Linux:
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.5/kubeseal-0.24.5-linux-amd64.tar.gz
tar -xvzf kubeseal-*.tar.gz kubeseal && sudo install -m 755 kubeseal /usr/local/bin/kubeseal
```

## Creating a SealedSecret

```bash
# 1. Create a regular secret YAML (DO NOT commit this)
cat <<EOF > /tmp/mlops-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: securemlops-secrets
  namespace: default
type: Opaque
stringData:
  MLFLOW_TRACKING_URI: "http://mlflow:5000"
  GRAFANA_ADMIN_PASSWORD: "your-secure-password"
  DB_CONNECTION_STRING: "postgresql://user:pass@host:5432/db"
EOF

# 2. Seal it with kubeseal
kubeseal --format yaml < /tmp/mlops-secret.yaml > k8s/sealed-secrets/sealed-secrets.yaml

# 3. Clean up the plaintext
rm /tmp/mlops-secret.yaml

# 4. Commit the sealed version (safe to store in git)
git add k8s/sealed-secrets/sealed-secrets.yaml
```

## Rotating Secrets

```bash
# Update the plaintext, re-seal, and apply
kubeseal --format yaml < /tmp/updated-secret.yaml > k8s/sealed-secrets/sealed-secrets.yaml
kubectl apply -f k8s/sealed-secrets/sealed-secrets.yaml
```

## Using Secrets in the Helm Chart

Enable in `values.yaml`:

```yaml
secrets:
  enabled: true
  useSealed: true
  data:
    MLFLOW_TRACKING_URI: ""       # Managed by SealedSecret
    GRAFANA_ADMIN_PASSWORD: ""    # Managed by SealedSecret
```

The deployment template mounts secrets as environment variables via `envFrom`.
