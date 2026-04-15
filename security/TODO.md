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
- Reduced Trivy findings from `50` to `7`
- Pushed `feature/security-scanning` to GitHub

## Next

- Decide whether to attempt a further Starlette/FastAPI upgrade to clear the last app-level finding
- Decide whether to accept or document the remaining base-image OS findings
- Prepare PR notes summarizing the scan reduction from `50` to `7`
- Share `security/INTEGRATION.md` with Nikhil for Jenkins integration
- Use the policy violation sample during final demo testing
