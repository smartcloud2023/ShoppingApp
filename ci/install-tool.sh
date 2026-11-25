#!/usr/bin/env bash
# Install a security tool from its official GitHub release and check the
# SHA-256 against the release's own checksums file before running it.
#
# Why not just use the vendor's GitHub Action? Because in March 2026 the
# trivy-action tags were force-pushed to malicious code. A pinned version plus
# a checksum check means a swapped binary fails here instead of running with
# our OIDC token in scope.
#
# usage: ci/install-tool.sh <trivy|gitleaks> <version-without-v>
set -euo pipefail

tool="${1:?tool name}"
version="${2:?version}"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
cd "$workdir"

case "$tool" in
  trivy)
    base="https://github.com/aquasecurity/trivy/releases/download/v${version}"
    archive="trivy_${version}_Linux-64bit.tar.gz"
    sums="trivy_${version}_checksums.txt"
    ;;
  gitleaks)
    base="https://github.com/gitleaks/gitleaks/releases/download/v${version}"
    archive="gitleaks_${version}_linux_x64.tar.gz"
    sums="gitleaks_${version}_checksums.txt"
    ;;
  *)
    echo "unknown tool: $tool" >&2
    exit 2
    ;;
esac

echo "Downloading $tool v$version"
curl -fsSLO "$base/$archive"
curl -fsSLO "$base/$sums"

# The checksums file lists every platform; pick our line and check only that.
# If the line is missing, grep fails and set -e stops the script.
grep " ${archive}\$" "$sums" | sha256sum --check --strict -

tar -xzf "$archive" "$tool"
sudo install -m 0755 "$tool" /usr/local/bin/"$tool"
"$tool" --version
