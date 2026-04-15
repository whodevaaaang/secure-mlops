# SecureMLOps - A Secure ML Model Delivery Pipeline

## Project Overview

12-week DevOps capstone combining DevSecOps + MLOps. Group project with 3 members.

## Team

- Devang (Lead) - Infrastructure & Deployment: Kubernetes, Helm, Ansible, Prometheus, Grafana, Evidently AI
- Yashasvi - Security Lead: SonarQube, Gitleaks, Bandit, Trivy, OPA
- Nikhil - CI/CD Pipeline Lead: Jenkins, Jenkinsfile

## Current State

- Week 1-2 COMPLETE: ML app (FastAPI + RandomForest loan prediction), Docker, Docker Compose (PostgreSQL + MLflow + API), 7 passing unit tests
- Week 3 COMPLETE: K8s manifests, Helm chart (deployment, service, servicemonitor, drift cronjob), Ansible playbooks (3 roles, 3 playbooks)
- Week 3 COMPLETE: Prometheus + Grafana monitoring (kube-prometheus-stack), 4 custom metrics, 4 Grafana dashboards
- Week 3 COMPLETE: Evidently AI drift detection (CronJob, Pushgateway, drift dashboard), prediction logging
- Week 3 COMPLETE: Rollback mechanism (rolling update strategy, rollback.sh, revision history)
- Week 3 COMPLETE: Architecture diagrams (3 Mermaid diagrams), comprehensive README
- Week 4 IN PROGRESS: Security integration with infrastructure (Trivy scanning in Helm flow, OPA policies, security Grafana dashboard)

## Tech Stack

- ML/API: Python 3.10, scikit-learn, FastAPI, MLflow, joblib, prometheus-fastapi-instrumentator
- Containers: Docker, Docker Compose
- Orchestration: Minikube (Kubernetes), Helm
- IaC: Ansible (3 roles: prerequisites, minikube, app_deploy)
- Monitoring: Prometheus + Grafana + Evidently AI + Pushgateway
- Security: Gitleaks, Bandit, SonarQube, Trivy, OPA
- CI/CD: Jenkins
- SCM: Git + GitHub with GitFlow branching

## Commands

- Run tests: cd ml-app && source venv/bin/activate && pytest tests/test_api.py -v
- Start Minikube: minikube start --driver=docker --cpus=2 --memory=4096
- Build image for Minikube: eval $(minikube docker-env) && cd ml-app && docker build -t secure-mlops-api:v1 .
- Deploy with Helm: helm install securemlops k8s/helm-chart/securemlops/
- Upgrade with Helm: helm upgrade securemlops k8s/helm-chart/securemlops/
- Port forward API: kubectl port-forward service/securemlops-service 8080:80
- Setup monitoring: cd monitoring && bash setup-monitoring.sh
- Port forward Grafana: kubectl port-forward svc/monitoring-grafana 3000:80
- Rollback: bash k8s/rollback.sh [revision]
- Ansible full setup: cd ansible && ansible-playbook playbooks/setup-environment.yml
- Ansible deploy only: cd ansible && ansible-playbook playbooks/deploy-app.yml
- Ansible teardown: cd ansible && ansible-playbook playbooks/teardown.yml
- Manual drift check: kubectl create job --from=cronjob/securemlops-drift-detection drift-manual-$(date +%s)
- Docker Compose (local): docker-compose up --build
- Trivy image scan: bash security/trivy-scan.sh [image:tag]
- OPA policy validation: bash security/validate-manifests.sh
- Export security metrics: bash security/security-metrics-exporter.sh [pushgateway_url]

## Git Workflow

- Branching: GitFlow (main, develop, feature/*)
- Commit convention: feat:, fix:, docs:, ci:, test:, chore:

## What Needs To Be Done Next

1. Populate Jenkins pipeline (ci/Jenkinsfile) with 8 stages
2. ~~Configure security tools (security/gitleaks.toml, security/trivy-config.yaml)~~ DONE
3. ~~Set up OPA policies~~ DONE - SonarQube integration still needed
4. Blue-green deployment strategy
5. Load testing and performance benchmarks
6. Screenshots for README dashboard placeholders
