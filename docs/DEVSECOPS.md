# E-commerce DevSecOps pipeline

## What runs, and in what order

| # | Stage | Tool | Blocks the build when | Where results go |
|---|-------|------|-----------------------|------------------|
| 1 | Secrets | Gitleaks (full history) | any secret found | Security tab (SARIF) |
| 2 | SAST | SonarQube | quality gate fails | Sonar + PR decoration |
| 3 | SCA | OWASP Dependency-Check | any CVSS >= 7 | Security tab + HTML artifact |
| 4 | FS / IaC | Trivy fs (vuln, secret, misconfig) | fixable HIGH/CRITICAL | Security tab |
| 5 | Image | Trivy image | fixable HIGH/CRITICAL | Security tab |
| 6 | Supply chain | CycloneDX SBOM + cosign keyless sign + attest | signing fails | ECR (signature + attestation) |
| 7 | Deploy dev | cosign verify, helm upgrade, smoke test | unsigned image, failed rollout, smoke fail | GitHub Environment `dev` |
| 8 | DAST | OWASP ZAP baseline | any FAIL rule in `security/zap-rules.tsv` | ZAP report artifact |
| 9 | Staging | same deploy | 1 reviewer must approve | Environment `staging` |
| 10 | Prod | same deploy | 2 reviewers + 10 min wait | Environment `prod` |

Stages 1 to 4 run in parallel. The build only starts when all four pass.
On a pull request, stages 1 to 5 run and nothing is pushed or deployed.

## Why it is built this way

- **No stored secrets.** Every job logs in to Vault with GitHub OIDC.
  Scanners, builders and deployers each get their own Vault role and policy.
  The prod deploy role is bound to the `environment: prod` claim, so it only
  works after the prod approval.
- **Shift left, fail cheap.** Secrets and code scans take a couple of minutes.
  Building 24 multi-arch images takes much longer, so it goes last.
- **Scan before push.** The image is built locally and scanned. Only a clean
  image is rebuilt multi-arch (from cache) and pushed.
- **Sign the digest, verify before deploy.** Tags can move, digests can't.
  `ci/verify-images.sh` refuses to deploy anything not signed by this
  workflow on `main`.
- **Pin everything.** Actions pinned to commit SHAs. Trivy and Gitleaks
  installed from release binaries with checksum checks (`ci/install-tool.sh`).
- **One deploy file for all envs.** `_deploy.yml` is the same for dev, staging
  and prod. The only differences are the values file and who approves.
- **Exceptions expire.** Suppressions in Dependency-Check and `.trivyignore`
  need a reason and an expiry date.

## Setup checklist

1. Run `vault/github-oidc-roles.sh` as a Vault admin, then `vault kv put` the values it prints.
2. Repo variable `VAULT_ADDR` (Settings -> Secrets and variables -> Variables).
3. GitHub Environments `dev`, `staging`, `prod` with branch rule `main`; reviewers on staging/prod.
4. Branch protection on `main`: PR required, 1 review, status checks required:
   `Secrets scan`, `SAST`, `SCA`, `Trivy fs + IaC scan`, every `Build *`.
5. In-cluster: External Secrets Operator + a `ClusterSecretStore` called `vault-ecommerce`,
   cert-manager, ingress-nginx with `add-headers` ConfigMap for security headers.
6. Delete `deployment/02-secrets.yaml` and rotate every value that was in it.
   It has been in git history, so treat it as leaked.

## What I would add next

- Kyverno / Sigstore policy-controller in the cluster so an unsigned image is
  rejected by the admission controller too, not just by the pipeline.
- Argo CD for the deploy (pull model), so the pipeline never holds cluster creds.
- Nightly ZAP full scan and a nightly Trivy re-scan of what is running (new CVEs appear after deploy).
- DefectDojo to collect all findings in one place with SLAs per severity.
- Renovate to keep action SHAs and base images up to date.
