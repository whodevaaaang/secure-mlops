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
- Findings: `7`
- Severity split: `7 HIGH`, `0 CRITICAL`

Notable packages:
- OS packages from the base image still contribute most of the remaining findings:
  - `libncursesw6`
  - `libsystemd0`
  - `libtinfo6`
  - `libudev1`
  - `ncurses-base`
  - `ncurses-bin`
- Remaining Python package finding:
  - `starlette 0.46.2`

## Remediation Summary

- Production image no longer installs `mlflow`, `pytest`, or `httpx`
- Production image now installs from `ml-app/requirements-runtime.txt`
- Docker build context excludes the local virtual environment
- Image build applies available `openssl` security updates
- Runtime image removes `pip`, `setuptools`, and `wheel`
- FastAPI upgraded to `0.115.14`
- Trivy findings improved from `50` to `7`

## Coordination Notes

- Devan should be told that the API image currently fails the container-security threshold.
- Nikhil should integrate the stages with artifact upload for:
  - `security/reports/generated/gitleaks-report.json`
  - `security/reports/generated/bandit-report.json`
  - `security/reports/generated/trivy-report.json`
  - `security/reports/generated/security-summary.json`
  - `security/reports/generated/security-summary.html`
