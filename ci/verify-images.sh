#!/usr/bin/env bash
# Refuse to deploy unless every image we are about to roll out was signed by
# our own pipeline, on main, in this repo. Reads the service list straight
# from the Helm values so the two can never drift apart.
#
# needs: ECR_REGISTRY, ECR_REPO_PREFIX, TAG, IDENTITY (set by _deploy.yml)
set -euo pipefail

: "${ECR_REGISTRY:?}" "${ECR_REPO_PREFIX:?}" "${TAG:?}" "${IDENTITY:?}"

: "${ENVIRONMENT:?}"
# Merge base values with the env file, same as Helm does, then list enabled services.
services=$(yq eval-all '. as $i ireduce ({}; . * $i)' \
    charts/ecommerce/values.yaml "charts/ecommerce/values-${ENVIRONMENT}.yaml" \
  | yq '.services | to_entries | .[] | select(.value.enabled != false) | (.value.image // .key)')

failed=0
for svc in $services; do
  ref="${ECR_REGISTRY}/${ECR_REPO_PREFIX}/${svc}:${TAG}"
  if cosign verify "$ref" \
       --certificate-identity "$IDENTITY" \
       --certificate-oidc-issuer https://token.actions.githubusercontent.com \
       >/dev/null 2>&1; then
    echo "ok       $svc"
  else
    echo "UNSIGNED $svc  ($ref)"
    failed=1
  fi
done

if [ "$failed" -ne 0 ]; then
  echo "One or more images failed signature verification. Not deploying." >&2
  exit 1
fi
