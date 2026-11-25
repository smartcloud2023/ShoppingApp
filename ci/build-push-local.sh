#!/usr/bin/env bash
# Build ONE service image on your laptop, scan it, and push it to Amazon ECR.
# Same steps and order as the pipeline, so you can try it before CI:
#
#   build (local only)  ->  Trivy scan (stop on fixable HIGH/CRITICAL)
#   ->  SBOM  ->  ECR repo (immutable tags, KMS, scan on push)  ->  push
#
# Run from the repo root, in WSL (Docker must work: `docker info`):
#   bash ci/build-push-local.sh cart
#   bash ci/build-push-local.sh frontend us-west-1
#
# Needs: docker, aws CLI logged in (aws sts get-caller-identity), git.
set -euo pipefail

SERVICE="${1:?usage: ci/build-push-local.sh <service> [aws-region]}"
REGION="${2:-${AWS_REGION:-$(aws configure get region || true)}}"
REGION="${REGION:-us-west-1}"
PREFIX="${ECR_REPO_PREFIX:-ecomerce}"            # same default as the pipeline
TRIVY_IMAGE="${TRIVY_IMAGE:-aquasec/trivy:0.76.2}" # pin a digest for real use

# service -> Dockerfile and the build args it needs (same table as the pipeline)
case "$SERVICE" in
  cart)            DOCKERFILE=src/cart/src/Dockerfile ;;
  ad|fraud-detection|kafka)
                   DOCKERFILE="src/$SERVICE/Dockerfile"; ARGS="OTEL_JAVA_AGENT_VERSION" ;;
  currency)        DOCKERFILE=src/currency/Dockerfile; ARGS="OPENTELEMETRY_CPP_VERSION" ;;
  opamp-server)    DOCKERFILE=src/opamp-server/Dockerfile; ARGS="OPAMP_GO_REF" ;;
  *)               DOCKERFILE="src/$SERVICE/Dockerfile" ;;
esac
[ -f "$DOCKERFILE" ] || { echo "No Dockerfile at $DOCKERFILE. Run from the repo root." >&2; exit 2; }

# Build args come from .env, exactly like CI
BUILD_ARGS=()
for name in ${ARGS:-}; do
  value=$(grep -E "^${name}=" .env | cut -d= -f2- | tr -d '\r')
  [ -n "$value" ] || { echo "$name missing from .env" >&2; exit 2; }
  BUILD_ARGS+=(--build-arg "${name}=${value}")
done

# Tag = git commit. Tags in ECR are immutable, so local uncommitted builds get
# a unique suffix instead of ever overwriting a real one.
TAG="$(git rev-parse --short=8 HEAD)"
if [ -n "$(git status --porcelain -- "src/$SERVICE" "$DOCKERFILE" 2>/dev/null)" ]; then
  TAG="${TAG}-local-$(date +%Y%m%d%H%M%S)"
fi

ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"
REPO="${PREFIX}/${SERVICE}"
LOCAL="local/${SERVICE}:${TAG}"
REMOTE="${REGISTRY}/${REPO}:${TAG}"

echo "== 1/5 build ${SERVICE} (${DOCKERFILE}) -> ${LOCAL}"
DOCKER_BUILDKIT=1 docker build -f "$DOCKERFILE" "${BUILD_ARGS[@]}" -t "$LOCAL" .

echo "== 2/5 Trivy scan (fails on fixable HIGH/CRITICAL)"
mkdir -p reports
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v "$PWD/reports:/out" \
  -v trivy-cache:/root/.cache "$TRIVY_IMAGE" \
  image --scanners vuln,secret --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 \
  --format table --output "/out/trivy-${SERVICE}.txt" "$LOCAL" \
  || { echo "Trivy found fixable HIGH/CRITICAL issues. Not pushing. See reports/trivy-${SERVICE}.txt" >&2; exit 1; }
echo "   clean. Report: reports/trivy-${SERVICE}.txt"

echo "== 3/5 SBOM (CycloneDX)"
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v "$PWD/reports:/out" \
  -v trivy-cache:/root/.cache "$TRIVY_IMAGE" \
  image --format cyclonedx --output "/out/sbom-${SERVICE}.cdx.json" "$LOCAL"

echo "== 4/5 ECR repository ${REPO} (${REGION})"
if ! aws ecr describe-repositories --region "$REGION" --repository-names "$REPO" >/dev/null 2>&1; then
  aws ecr create-repository --region "$REGION" --repository-name "$REPO" \
    --image-tag-mutability IMMUTABLE \
    --image-scanning-configuration scanOnPush=true \
    --encryption-configuration encryptionType=KMS >/dev/null
  echo "   created"
fi
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY" >/dev/null

echo "== 5/5 push ${REMOTE}"
docker tag "$LOCAL" "$REMOTE"
docker push "$REMOTE" | tail -1
docker logout "$REGISTRY" >/dev/null

echo
echo "Done: ${REMOTE}"
echo "ECR's own scan: aws ecr describe-image-scan-findings --region ${REGION} --repository-name ${REPO} --image-id imageTag=${TAG} --query 'imageScanFindings.findingSeverityCounts'"
