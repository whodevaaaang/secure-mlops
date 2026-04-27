# Infrastructure as Code Reference

This document describes the Infrastructure as Code (IaC) layer of SecureMLOps. The entire environment — from installing tools to deploying the application — is defined in code and reproducible with single commands.

## Why Infrastructure as Code

Manual environment setup creates three problems: instructions go stale, every developer's machine ends up slightly different, and onboarding takes hours. IaC solves all three by making the setup itself executable. A new contributor runs one command and ends up with an environment identical to everyone else's.

## Ansible

Ansible is the automation tool that drives our environment provisioning. It connects to a target machine and runs tasks defined in YAML playbooks. The defining property of Ansible tasks is that they are idempotent — running a playbook twice produces the same end state as running it once. Tasks only execute when the system is not already in the desired state, which means re-running playbooks is always safe.

### Ansible Roles

A role is a self-contained, reusable unit of automation. Instead of one giant playbook with hundreds of tasks, we split work into three focused roles.

#### Role 1: prerequisites
Installs the foundational tools required by every other component. Specifically: Docker Engine, kubectl (the Kubernetes command-line client), Minikube (local Kubernetes cluster), and Helm (Kubernetes package manager). The role detects the operating system and installs the appropriate package for each tool, handling apt repositories on Ubuntu and other package sources where needed.

#### Role 2: minikube
Manages the lifecycle of the local Kubernetes cluster. Starts Minikube with the Docker driver, allocates appropriate CPU and memory resources, and enables required addons including ingress and metrics-server. Also handles cluster shutdown and reset cleanly.

#### Role 3: app_deploy
Handles application deployment. Builds the Docker image inside the Minikube Docker context (so the cluster can find the image without a registry push), then runs Helm to install or upgrade the SecureMLOps release with appropriate values.

### Ansible Playbooks

Playbooks orchestrate roles in sequence. We have three.

#### setup-environment.yml
The first-time setup playbook. Runs prerequisites and minikube roles. After this completes, the developer has Docker, Kubernetes, Helm, kubectl, and a running cluster — ready to deploy the app.

#### deploy-app.yml
Runs the app_deploy role. Used both for first deployment and for redeploying after code changes during local development.

#### teardown.yml
Cleanly removes the SecureMLOps release, stops Minikube, and optionally removes installed tools. Used to reset to a clean state.

## Makefile

The Makefile is a thin convenience layer over the longer commands developers use throughout the day. Instead of typing `helm upgrade --install securemlops k8s/helm-chart/securemlops/`, a developer types `make deploy`. This standardizes commands across the team — everyone uses the same vocabulary regardless of platform.

### Target Categories

#### Setup and Cleanup
- `make install` — runs the full Ansible setup playbook
- `make clean` — removes the Helm release and stops Minikube
- `make reset` — full teardown and reinstall

#### Deployment
- `make build` — builds the Docker image inside Minikube's Docker context
- `make deploy` — Helm upgrade/install with default rolling deployment
- `make deploy-blue-green` — Helm deploy using blue-green strategy values
- `make deploy-canary` — Helm deploy using canary strategy values
- `make rollback` — invokes helm rollback to the previous revision

#### Testing
- `make test` — runs pytest with the JUnit reporter
- `make lint` — runs flake8 across the codebase
- `make load-test` — runs the load test against the local deployment

#### Security
- `make scan-secrets` — runs Gitleaks against the repo
- `make scan-code` — runs Bandit against ml-app
- `make scan-image` — runs Trivy against the built Docker image
- `make scan-policies` — validates manifests against OPA policies
- `make scan-all` — runs all four scans in sequence

#### Monitoring and Observability
- `make monitor` — port-forwards Grafana and Prometheus to localhost
- `make logs` — tails the API pod logs
- `make pods` — shows current pod status
- `make dashboard` — opens the Minikube Kubernetes dashboard

#### Drift Detection
- `make drift-check` — manually triggers an Evidently AI drift report

In total, the Makefile defines over 25 targets covering every routine operation a developer needs.

## How It All Fits Together

A new contributor's first day looks like this. They clone the repo, run `make install`, and Ansible installs every tool, starts Minikube, builds the image, and deploys the app via Helm. Less than 15 minutes later, they can hit the API at `localhost:8080/docs` and see Grafana dashboards at `localhost:31000`. Without IaC, the same setup typically takes hours and requires a maintained setup document that drifts out of date.
