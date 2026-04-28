.PHONY: help setup deploy teardown test lint security-scan monitoring load-test \
       build rollback blue-green-status canary-status clean

SHELL := /bin/bash
VENV := ml-app/venv/bin

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# ---- Setup & Deploy ----

setup: ## Full environment setup via Ansible (prerequisites + minikube + app)
	cd ansible && ansible-playbook playbooks/setup-environment.yml

deploy: ## Deploy/upgrade app on existing cluster via Ansible
	cd ansible && ansible-playbook playbooks/deploy-app.yml

teardown: ## Tear down the entire environment
	cd ansible && ansible-playbook playbooks/teardown.yml

build: ## Build Docker image in Minikube
	eval $$(minikube docker-env) && cd ml-app && docker build -t secure-mlops-api:v1 .

monitoring: ## Setup Prometheus + Grafana monitoring stack
	cd monitoring && bash setup-monitoring.sh

# ---- Testing ----

test: ## Run unit tests
	cd ml-app && $(VENV)/pytest tests/test_api.py -v

lint: ## Run flake8 linting
	cd ml-app && $(VENV)/flake8 api/ tests/ --max-line-length=120 --exclude=venv,__pycache__

load-test: ## Run Locust load test benchmark (50 users, 60s)
	bash tests/load/run-benchmark.sh --users 50 --duration 60

load-test-ui: ## Start Locust web UI on port 8089
	cd ml-app && $(VENV)/locust -f ../tests/load/locustfile.py --host http://localhost:8080

# ---- Security ----

security-scan: ## Run all security scans (Gitleaks, Bandit, Trivy, OPA)
	@echo "=== Gitleaks ===" && gitleaks detect --source=. --config=security/gitleaks.toml --verbose || true
	@echo ""
	@echo "=== Bandit ===" && cd ml-app && $(VENV)/bandit -r api/ --severity-level medium --confidence-level medium || true
	@echo ""
	@echo "=== Trivy ===" && bash security/trivy-scan.sh secure-mlops-api:v1 || true
	@echo ""
	@echo "=== OPA ===" && bash security/validate-manifests.sh || true

trivy: ## Run Trivy image scan
	bash security/trivy-scan.sh secure-mlops-api:v1

opa: ## Run OPA policy validation
	bash security/validate-manifests.sh

# ---- Deployment Strategies ----

rollback: ## Roll back to previous Helm revision
	bash k8s/rollback.sh

blue-green-status: ## Show blue-green deployment status
	bash k8s/blue-green-switch.sh --status

blue-green-switch: ## Switch blue-green traffic to inactive slot
	bash k8s/blue-green-switch.sh

canary-status: ## Show canary deployment status
	bash k8s/canary-promote.sh --status

canary-promote: ## Auto-promote canary if healthy
	bash k8s/canary-promote.sh --auto

# ---- MLflow ----

train: ## Train the ML model (with optional MLflow tracking)
	cd ml-app && $(VENV)/python model/train.py

model-list: ## List MLflow model versions
	bash scripts/promote-model.sh --list

model-deploy: ## Deploy latest Production model from MLflow
	bash scripts/promote-model.sh --deploy

# ---- Helm ----

helm-install: ## Install Helm release
	helm install securemlops k8s/helm-chart/securemlops/

helm-upgrade: ## Upgrade Helm release
	helm upgrade securemlops k8s/helm-chart/securemlops/

helm-template: ## Render Helm templates (dry-run)
	helm template securemlops k8s/helm-chart/securemlops/

# ---- Jenkins ----

jenkins-up: ## Start Jenkins + SonarQube locally
	docker-compose -f docker-compose.jenkins.yml up -d

jenkins-down: ## Stop Jenkins + SonarQube
	docker-compose -f docker-compose.jenkins.yml down

jenkins-tools: ## Install tools inside Jenkins container
	docker exec securemlops-jenkins bash /workspace/ci/scripts/setup-jenkins-tools.sh

# ---- Cleanup ----

clean: ## Remove generated files (reports, caches, test results)
	rm -rf tests/load/results/ security/reports/*.json ml-app/test-results.xml
	rm -rf ml-app/.pytest_cache ml-app/__pycache__
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
