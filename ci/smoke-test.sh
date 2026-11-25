#!/usr/bin/env bash
# Quick "is it alive" check after a deploy. Not a test suite, just enough to
# catch a broken rollout before DAST or the next environment.
# usage: ci/smoke-test.sh https://shop.dev.example.com
set -euo pipefail

url="${1:?base url}"
attempts=10

check() {
  local path="$1" expect="$2"
  for i in $(seq 1 "$attempts"); do
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "${url}${path}" || true)
    if [ "$code" = "$expect" ]; then
      echo "ok   ${path} -> ${code}"
      return 0
    fi
    echo "wait ${path} -> ${code} (try ${i}/${attempts})"
    sleep 6
  done
  echo "FAIL ${path} never returned ${expect}" >&2
  return 1
}

check "/"                        200
check "/api/products"            200
check "/api/recommendations"     200
check "/feature"                 200

# Security headers should be set by the ingress, check they really are.
headers=$(curl -sI --max-time 10 "$url/")
for h in strict-transport-security x-content-type-options; do
  if ! grep -qi "^${h}:" <<<"$headers"; then
    echo "FAIL missing header: $h" >&2
    exit 1
  fi
done
echo "Smoke test passed for $url"
