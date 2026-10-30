#!/usr/bin/env bash
set -euo pipefail
version=8.24.3
archive="gitleaks_${version}_linux_x64.tar.gz"
stage=$(mktemp -d)
trap 'python3 -c "import shutil,sys; shutil.rmtree(sys.argv[1])" "$stage"' EXIT
cd "$stage"
curl --fail --location --retry 3 \
  "https://github.com/gitleaks/gitleaks/releases/download/v${version}/${archive}" -o "$archive"
echo "9991e0b2903da4c8f6122b5c3186448b927a5da4deef1fe45271c3793f4ee29c  $archive" | sha256sum --check
tar -xzf "$archive" gitleaks
mkdir -p "$GITHUB_WORKSPACE/.ci-bin"
install -m 755 gitleaks "$GITHUB_WORKSPACE/.ci-bin/gitleaks"
echo "$GITHUB_WORKSPACE/.ci-bin" >> "$GITHUB_PATH"
