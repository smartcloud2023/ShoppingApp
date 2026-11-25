#!/usr/bin/env bash
# One-off clean-up of the e-commerce repo. Run from the repo root in Git Bash or WSL:
#   bash cleanup.sh
# Everything is removed with "git rm", so it stays in git history and can be
# brought back with:  git checkout HEAD~1 -- <path>
set -euo pipefail
cd "$(dirname "$0")"
[ -d .git ] || { echo "Run this from the Ecommerce-project repo root"; exit 1; }

gone() { for p in "$@"; do
  if git ls-files --error-unmatch "$p" >/dev/null 2>&1 || [ -n "$(git ls-files "$p")" ]; then
    git rm -r -q "$p"
  fi
  rm -rf "$p"
  echo "removed  $p"
done; }

# 1. New pipeline in, old one out
mkdir -p .github/workflows
if [ -d ci/workflows-to-move ]; then
  mv ci/workflows-to-move/devsecops.yml ci/workflows-to-move/_deploy.yml .github/workflows/
fi
git add .github/workflows/devsecops.yml .github/workflows/_deploy.yml
gone .github/workflows/ecr-build-push.yml ci/workflows-to-move

# 2. JVM crash dumps (junk)
gone hs_err_pid*.log replay_pid*.log

# 3. Replaced by the new setup
gone vault              # GitHub OIDC replaced Vault
gone deployment         # Helm chart (charts/ecommerce) is the only deploy path
gone docs/ci            # doc for the old ECR-only pipeline

# 4. Extra compose variants and upstream dev tooling (compose.yaml + .env stay)
gone compose.agent.yaml compose.extras.yaml compose.full.yaml \
     compose.observability.yaml compose.profiling.yaml compose.tests.yaml \
     .env.override Makefile buildkitd.toml docker-gen-proto.sh ide-gen-proto.sh

# 5. Upstream OpenTelemetry-demo project files we don't use
gone CHANGELOG.md CONTRIBUTING.md .licenserc.json .lychee.toml \
     .markdownlint.yaml .yamllint .yamlignore package.json package-lock.json \
     internal test src/react-native-app .qodo

# 6. Docs and AI-assistant files - keep code only
gone docs README.md AGENTS.md CLAUDE.md .claude

# 7. Local docker-compose run - not app code or pipeline
#    (.env stays: the pipeline reads build-arg versions from it)
gone compose.yaml otel-config.yml
echo
git status --short | head -60
echo
echo "Review the list above, then delete this script (rm cleanup.sh) and:"
echo "  git commit -m 'chore: slim repo down to app, Helm chart and DevSecOps pipeline'"
echo "  git push"
