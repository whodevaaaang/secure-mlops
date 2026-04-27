# CI/CD Pipeline Reference

This document describes the Jenkins CI/CD pipeline that automates the journey from code commit to production deployment. The pipeline is defined as code in `ci/Jenkinsfile` and runs automatically on every push to `main` or `develop` via a GitHub webhook.

## Pipeline Philosophy
The pipeline implements a fail-fast, quality-gated approach. Each of the 12 stages is a checkpoint — if any stage fails, the pipeline stops immediately and deployment is blocked. This guarantees that only code passing every quality, security, and policy check reaches production.

## The 12 Stages

### Stage 1: Checkout
Pulls the latest code from GitHub into the Jenkins workspace using the commit SHA that triggered the build.

### Stage 2: Install Dependencies
Creates a Python virtual environment (`venv`) and installs packages from `requirements.txt`. The pip cache is preserved between builds for faster execution.

### Stage 3: Lint
Runs `flake8` against the codebase to enforce PEP 8 style and catch syntax errors, unused imports, and undefined variables. Any error fails the stage.

### Stage 4: Unit Tests
Executes `pytest` across all test files. Generates a JUnit XML report that Jenkins parses and displays visually, showing pass/fail counts and execution time per test.

### Stage 5: Security Scan (Parallel)
Runs Gitleaks and Bandit in parallel to save time. Gitleaks scans the entire Git history for committed secrets. Bandit scans Python source for insecure patterns. Either tool finding a HIGH severity issue fails the stage.

### Stage 6: SonarQube Analysis
Submits code to a SonarQube server running in Docker. The quality gate enforces zero critical bugs, zero security vulnerabilities, and minimum code coverage. The pipeline waits for SonarQube's verdict before proceeding.

### Stage 7: Docker Build
Builds the container image using a multi-stage Dockerfile. The image is tagged with the Git commit SHA (e.g., `secure-mlops-api:abc1234`) for full traceability between deployed images and source code.

### Stage 8: Image Vulnerability Scan
Trivy scans the built image against the CVE database. Any CRITICAL or HIGH severity vulnerability blocks deployment.

### Stage 9: Policy Validation
OPA evaluates the Kubernetes manifests against 12 Rego policies covering non-root execution, resource limits, health probes, and other production requirements.

### Stage 10: Helm Deploy
Runs `helm upgrade --install` to deploy to the Minikube cluster. This stage only runs on the `main` and `develop` branches — feature branches do not deploy. Helm tracks revision history (5 most recent revisions kept) for one-command rollback.

### Stage 11: Health Verification
Waits for pods to enter the `Running` state, then curls the `/health` endpoint to confirm the API is responding correctly.

### Stage 12: Load Test (Optional)
A parameterized stage that runs a load test (30 concurrent users, 30 seconds) to validate performance under stress. Skipped by default to keep pipeline runs fast.

## Pipeline Features

### Pipeline as Code
The entire pipeline definition lives in `ci/Jenkinsfile` inside the repository. This means the pipeline is version-controlled, reviewable through Pull Requests, and reproducible across Jenkins instances.

### Caching Strategy
The pipeline caches three things between builds: pip downloaded packages, Docker image layers, and Trivy's vulnerability database. This significantly reduces build time after the first run.

### Deployment Strategy as a Parameter
Stage 10 accepts a deployment strategy parameter — rolling, blue-green, or canary — allowing the same pipeline to support different deployment patterns based on the change risk level.

### Artifacts Archived
JUnit test reports, Bandit JSON output, Trivy scan results, and SonarQube reports are all archived as Jenkins artifacts and accessible from the build dashboard.

### Webhook Trigger
GitHub fires a webhook to Jenkins on every push, triggering the pipeline within seconds. No polling, no manual triggers required.

## Failure Handling
When any stage fails: the pipeline stops, subsequent stages are skipped, the build is marked failed, and notifications are sent. The developer must fix the issue and push again, which triggers a fresh pipeline run.
