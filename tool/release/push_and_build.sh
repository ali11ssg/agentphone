#!/usr/bin/env bash
# Pushes the fork to GitHub, uploads the signing key as a secret, and watches
# the build.
#
# Run this once, after `gh auth login`:
#
#   bash tool/release/push_and_build.sh
#
# The keystore lives outside the repository (keystore/ is git-ignored). This
# script reads it, uploads it as a repository secret and never prints it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
KEYSTORE_DIR="$ROOT/../keystore"
KEYSTORE="$KEYSTORE_DIR/agentphone-release.p12"
CREDENTIALS="$KEYSTORE_DIR/credentials.txt"
REPO="${AGENTPHONE_REPO:-agentphone}"

cd "$ROOT"

if ! gh auth status > /dev/null 2>&1; then
  echo "Not signed in to GitHub. Run: gh auth login --web" >&2
  exit 1
fi

if [ ! -f "$KEYSTORE" ] || [ ! -f "$CREDENTIALS" ]; then
  echo "The signing key is missing. Run: bash tool/keystore/make_keystore.sh" >&2
  exit 1
fi

# The alias and the password come from the credentials file, never from here.
alias_name="$(sed -n 's/^alias=//p' "$CREDENTIALS")"
password="$(sed -n 's/^storePassword=//p' "$CREDENTIALS")"

if gh repo view "$REPO" > /dev/null 2>&1; then
  echo "Repository $REPO already exists; pushing to it."
  git remote remove origin 2> /dev/null || true
  git remote add origin "https://github.com/$(gh api user --jq .login)/$REPO.git"
else
  gh repo create "$REPO" \
    --public \
    --description "A coding agent on your phone: Linux, an agent engine, and a Computer panel." \
    --source=. \
    --remote=origin
fi

git push -u origin main

echo "Uploading the signing key as a repository secret..."
base64 -w0 "$KEYSTORE" | gh secret set AGENTPHONE_KEYSTORE_B64
printf '%s' "$password" | gh secret set AGENTPHONE_KEYSTORE_PASSWORD
printf '%s' "$alias_name" | gh secret set AGENTPHONE_KEY_ALIAS

echo "Starting the build..."
git tag -f "v$(grep -m1 '^version:' pubspec.yaml | cut -d' ' -f2 | cut -d'+' -f1)" \
  -m "AgentPhone release"
git push origin --tags

gh run list --limit 3
echo
echo "Watch it with: gh run watch"
echo "Download the APK from: https://github.com/$(gh api user --jq .login)/$REPO/releases"
