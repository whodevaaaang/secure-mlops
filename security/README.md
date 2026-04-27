# DevSecOps Security Tooling

This document describes the five security tools integrated into the SecureMLOps pipeline. Each tool catches a different category of issue, providing defense in depth.

## 1. Gitleaks
Scans the entire Git history for accidentally committed secrets such as API keys, passwords, and tokens. Even if a secret is later removed from the code, it remains in Git history — Gitleaks finds these. Configured via `security/gitleaks.toml`.

## 2. Bandit
Python-specific security linter. Analyzes our source code for insecure patterns including hardcoded credentials, use of insecure hash functions (MD5, SHA1), SQL injection risks, and dangerous functions like `eval()` and `exec()`. Each finding is assigned a severity: LOW, MEDIUM, or HIGH.

## 3. SonarQube
Static code analysis platform that runs in Docker. Performs deep analysis covering code quality (bugs, complexity, code smells), security hotspots, and test coverage. Enforces a quality gate that blocks deployment if code does not meet defined thresholds.

## 4. Trivy
Container image vulnerability scanner. Checks both OS packages and application libraries inside our Docker image against the CVE (Common Vulnerabilities and Exposures) database. The pipeline is configured to fail if any CRITICAL or HIGH severity CVEs are detected.

## 5. OPA (Open Policy Agent)
Policy engine that validates Kubernetes manifests against rules written in Rego. We enforce 12 policies covering: non-root containers, required resource limits, required liveness and readiness probes, no use of `hostPort`, and other production-readiness checks. Any policy violation blocks deployment.

## Pipeline Integration
All five tools run automatically inside the Jenkins CI/CD pipeline. Gitleaks and Bandit run in parallel during stage 5. SonarQube runs in stage 6 with a quality gate. Trivy scans the built image in stage 8. OPA validates manifests in stage 9. Failure at any stage blocks deployment.

## Runtime Hardening
Beyond pipeline scans, we also enforce runtime hardening: RBAC for least-privilege access, network policies for pod-to-pod traffic control, SealedSecrets for safe secret management in Git, and non-root user enforcement on all containers.
