# SecureMLOps - A Secure ML Model Delivery Pipeline

## Project Overview

12-week DevOps capstone combining DevSecOps + MLOps. Group project with 3 members.

## Team

- Devang (Lead) - Infrastructure & Deployment: Kubernetes, Helm, Ansible, Prometheus, Grafana, Evidently AI

- Yashasvi - Security Lead: SonarQube, Gitleaks, Bandit, Trivy, OPA

- Nikhil - CI/CD Pipeline Lead: Jenkins, Jenkinsfile

## Current State

- Week 1-2 COMPLETE: ML app (FastAPI + RandomForest loan prediction), Docker, Docker Compose (PostgreSQL + MLflow + API), 7 passing unit tests

- Week 3 IN PROGRESS: Minikube running, ML API deployed to K8s (2 replicas), Helm chart created

- Active branch: feature/k8s-infrastructure

## Tech Stack

- ML/API: Python 3.10, scikit-learn, FastAPI, MLflow, joblib

- Containers: Docker, Docker Compose

- Orchestration: Minikube (Kubernetes), Helm

- IaC: Ansible (planned)

- Monitoring: Prometheus + Grafana (planned)

- SCM: Git + GitHub with GitFlow branching

## Commands

- Run tests: cd ml-app && source venv/bin/activate && pytest tests/test_api.py -v

- Start Minikube: minikube start --driver=docker

- Build image for Minikube: eval $(minikube docker-env) && cd ml-app && docker build -t secure-mlops-api:v1 .

- Deploy with Helm: helm install securemlops k8s/helm-chart/securemlops/

- Port forward: kubectl port-forward service/securemlops-service 8080:80

## Git Workflow

- Branching: GitFlow (main, develop, feature/*)

- Current branch: feature/k8s-infrastructure

- Commit convention: feat:, fix:, docs:, ci:, test:, chore:

## What Needs To Be Done Next

1. Commit K8s manifests + Helm chart, push, create PR

2. Write Ansible playbooks for environment automation

3. Deploy Prometheus + Grafra on K8s

4. Set up Evidently AI for drift detection

5. Rollback mechanism, blue-green deployment

6. Documentation and architecture diagrams
