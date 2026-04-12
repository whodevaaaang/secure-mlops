# Security Workstream

This directory contains the DevSecOps deliverables for the `feature/security-scanning` branch.

## Scope

- Secret detection with Gitleaks
- Python static analysis with Bandit
- Container vulnerability scanning with Trivy
- Admission-style policy checks with OPA/Rego
- JSON and HTML report generation for scan outputs

## Files

- `gitleaks.toml`: repository secret scanning rules
- `bandit.yml`: Python security scan configuration for `ml-app/`
- `trivy-config.yaml`: container vulnerability scan configuration
- `opa-policies/`: Rego policies for deployment and compliance checks

## Recommended Scan Commands

### Gitleaks

```bash
docker run --rm \
  -v "$PWD:/repo" \
  ghcr.io/gitleaks/gitleaks:latest detect \
  --source=/repo \
  --config=/repo/security/gitleaks.toml \
  --report-format=json \
  --report-path=/repo/security/reports/generated/gitleaks-report.json
```

### Bandit

```bash
python3 -m pip install bandit
bandit -r ml-app -c security/bandit.yml -f json -o security/reports/generated/bandit-report.json
```

### Trivy

```bash
docker build -t securemlops-api:local ./ml-app
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$PWD:/workdir" \
  aquasec/trivy image \
  --config /workdir/security/trivy-config.yaml \
  securemlops-api:local
```

### OPA

```bash
opa eval --format pretty \
  --data security/opa-policies \
  --input security/examples/policy-input.json \
  "data.securemlops.security.deny"
```

## Reporting

Use `scripts/generate_security_report.py` to combine scan results into JSON and HTML summaries under `security/reports/generated/`.
