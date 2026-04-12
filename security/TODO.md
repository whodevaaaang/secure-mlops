# Yashi Progress

## Completed

- Added `gitleaks` configuration
- Added `bandit` configuration
- Added `trivy` configuration
- Added OPA/Rego policies
- Added sample pass/fail OPA inputs
- Added security report generation script
- Verified app baseline with `pytest` (`7 passed`)
- Ran local Gitleaks scan (`0` findings)
- Ran local Bandit scan (`0` findings)
- Ran local OPA validation
- Ran local Trivy scan (`50` findings)
- Pushed `feature/security-scanning` to GitHub

## Next

- Reduce Trivy findings by updating vulnerable packages and/or base image
- Prepare a second commit focused on remediation
- Share `security/INTEGRATION.md` with Nikhil for Jenkins integration
- Use the policy violation sample during final demo testing
