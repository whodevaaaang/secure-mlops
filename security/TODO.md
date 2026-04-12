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
- Reduced Trivy findings from `50` to `9`
- Pushed `feature/security-scanning` to GitHub

## Next

- Try a FastAPI/Starlette upgrade in a separate safe pass
- Decide whether to accept or document the remaining base-image OS findings
- Prepare a second commit focused on remediation
- Share `security/INTEGRATION.md` with Nikhil for Jenkins integration
- Use the policy violation sample during final demo testing
