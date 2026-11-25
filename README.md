# E-commerce microservices – DevSecOps on AWS

A 24-service online shop (based on the OpenTelemetry demo) with a secure CI/CD
pipeline: every change is scanned, every image is built, scanned, signed and
pushed to Amazon ECR, then deployed to EKS with Helm.

## Repo layout

| Path | What it is |
|---|---|
| `src/` | Source code and Dockerfile for each service |
| `pb/` | Shared gRPC contract (`demo.proto`) used by the services |
| `telemetry-schema/` | Telemetry definitions used by the `telemetry-docs` image |
| `charts/ecommerce/` | Helm chart, with `values-dev/staging/prod.yaml` |
| `.github/workflows/devsecops.yml` | The pipeline |
| `.github/workflows/_deploy.yml` | Reusable deploy job (dev → staging → prod) |
| `ci/` | Helper scripts (tool install, local build/push, image verify, smoke test) |
| `security/` | Trivy config, Dependency-Check suppressions, ZAP rules |
| `docs/` | `DEVSECOPS.md` and the pipeline diagram |
| `compose.yaml`, `.env` | Run the shop locally |

## Pipeline

1. **Secrets scan** – Gitleaks (always blocks)
2. **SAST** – SonarCloud with quality gate
3. **SCA** – OWASP Dependency-Check (fails on CVSS ≥ 7)
4. **Trivy fs + IaC** – code, Dockerfiles, Helm chart
5. **Build** – per service: Trivy image scan → SBOM → push to ECR → cosign sign
6. **Deploy** – dev → OWASP ZAP baseline → staging (approval) → prod (approval)

AWS access is GitHub OIDC (no stored keys). Scan gates only block once the
repository variable `ENFORCE_SECURITY_GATES=true`; deploys run once
`DEPLOY_ENABLED=true`. Details in [docs/DEVSECOPS.md](docs/DEVSECOPS.md).

## Run locally

```bash
docker compose up -d --build
# shop: http://localhost:8080
```

## Build and push one image by hand

```bash
bash ci/build-push-local.sh frontend
```
