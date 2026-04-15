#!/bin/bash
# Install required tools inside the Jenkins container
# Run once after Jenkins starts: docker exec securemlops-jenkins bash /workspace/ci/scripts/setup-jenkins-tools.sh

set -euo pipefail

echo "=== Installing CI/CD Tools in Jenkins Container ==="

apt-get update -qq

# Python 3.10 + pip
echo "[1/7] Installing Python..."
apt-get install -y -qq python3 python3-pip python3-venv > /dev/null

# Docker CLI (for building images)
echo "[2/7] Installing Docker CLI..."
apt-get install -y -qq docker.io > /dev/null 2>&1 || {
    curl -fsSL https://get.docker.com | sh
}

# Helm
echo "[3/7] Installing Helm..."
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# kubectl
echo "[4/7] Installing kubectl..."
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl

# Trivy
echo "[5/7] Installing Trivy..."
curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin

# Conftest (OPA)
echo "[6/7] Installing conftest..."
CONFTEST_VERSION=$(curl -s https://api.github.com/repos/open-policy-agent/conftest/releases/latest | grep tag_name | cut -d '"' -f 4 | sed 's/v//')
curl -LO "https://github.com/open-policy-agent/conftest/releases/download/v${CONFTEST_VERSION}/conftest_${CONFTEST_VERSION}_Linux_x86_64.tar.gz"
tar xzf "conftest_${CONFTEST_VERSION}_Linux_x86_64.tar.gz" -C /usr/local/bin conftest
rm "conftest_${CONFTEST_VERSION}_Linux_x86_64.tar.gz"

# Gitleaks
echo "[7/7] Installing Gitleaks..."
GITLEAKS_VERSION=$(curl -s https://api.github.com/repos/gitleaks/gitleaks/releases/latest | grep tag_name | cut -d '"' -f 4 | sed 's/v//')
curl -LO "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz"
tar xzf "gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" -C /usr/local/bin gitleaks
rm "gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz"

echo ""
echo "=== Installed Versions ==="
python3 --version
docker --version 2>/dev/null || echo "Docker: not available (mount socket)"
helm version --short
kubectl version --client --short 2>/dev/null || kubectl version --client
trivy --version
conftest --version
gitleaks version

echo ""
echo "=== Setup Complete ==="
echo "Configure Jenkins credentials:"
echo "  1. sonarqube-url:   http://securemlops-sonarqube:9000"
echo "  2. sonarqube-token: Generate at SonarQube > My Account > Security > Tokens"
echo ""
echo "Install Jenkins plugins:"
echo "  - Pipeline"
echo "  - Git"
echo "  - JUnit"
echo "  - SonarQube Scanner"
echo "  - Docker Pipeline"
echo "  - Kubernetes CLI"
