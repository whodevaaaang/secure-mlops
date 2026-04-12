# Security Integration Handoff

This file is the handoff for the CI/CD owner to integrate security checks into Jenkins.

## Required Tools

- Gitleaks
- Bandit
- Trivy
- OPA

## Expected Config Paths

- `security/gitleaks.toml`
- `security/bandit.yml`
- `security/trivy-config.yaml`
- `security/opa-policies/`
- `security/examples/policy-input.json`
- `security/examples/policy-violation-input.json`

## Recommended Jenkins Stage Order

1. `gitleaks-scan`
2. `bandit-scan`
3. `docker-build`
4. `trivy-scan`
5. `opa-policy-check`

## Suggested Commands

### Gitleaks

```bash
docker run --rm \
  -v "$WORKSPACE:/repo" \
  ghcr.io/gitleaks/gitleaks:latest detect \
  --source=/repo \
  --config=/repo/security/gitleaks.toml \
  --report-format=json \
  --report-path=/repo/security/reports/generated/gitleaks-report.json
```

Fail condition:
- Any detected secret

### Bandit

```bash
python3 -m pip install bandit
bandit -r ml-app \
  -c security/bandit.yml \
  -f json \
  -o security/reports/generated/bandit-report.json
```

Fail condition:
- Any Bandit finding with `MEDIUM` or `HIGH` severity

### Docker Build

```bash
docker build -t securemlops-api:${GIT_COMMIT} ./ml-app
```

### Trivy

```bash
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$WORKSPACE:/workdir" \
  ghcr.io/aquasecurity/trivy:latest image \
  --config /workdir/security/trivy-config.yaml \
  --output /workdir/security/reports/generated/trivy-report.json \
  securemlops-api:${GIT_COMMIT}
```

Fail condition:
- Any `HIGH` or `CRITICAL` vulnerability

### OPA

```bash
docker run --rm \
  -v "$WORKSPACE:/workdir" \
  openpolicyagent/opa:latest eval \
  --format pretty \
  --data /workdir/security/opa-policies \
  --input /workdir/security/examples/policy-input.json \
  "data.securemlops.security.deny"
```

Fail condition:
- `data.securemlops.security.deny` returns any non-empty array

## Current Local Scan Results

### Gitleaks

- Status: pass
- Findings: `0`

### Bandit

- Status: pass
- Findings: `0`

### Trivy

- Status: fail
- Findings: `50`
- Severity split: `43 HIGH`, `7 CRITICAL`

Notable packages:
- `mlflow 2.9.2`: multiple `CRITICAL` findings, fixed in `2.10.0`
- `gunicorn 21.2.0`: `HIGH` findings, fixed in `22.0.0`
- `openssl 3.5.5-1~deb13u1`: `HIGH` findings, fixed in `3.5.5-1~deb13u2`

## Coordination Notes

- Devan should be told that the API image currently fails the container-security threshold.
- Nikhil should integrate the stages with artifact upload for:
  - `security/reports/generated/gitleaks-report.json`
  - `security/reports/generated/bandit-report.json`
  - `security/reports/generated/trivy-report.json`
  - `security/reports/generated/security-summary.json`
  - `security/reports/generated/security-summary.html`
