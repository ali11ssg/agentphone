#!/usr/bin/env bash
# Applies the fork's identity to a checkout of the upstream project.
#
#   bash tool/fork/apply_fork.sh [repo-root]
#
# It renames the Android application id and the Kotlin package, moves the
# Dart package name, and switches the deep-link scheme. Everything else about
# the app stays as the upstream project built it.
set -euo pipefail

ROOT="${1:-$(pwd)}"
OLD_PKG="io.github.eslamasabry.opencode_mobile"
NEW_PKG="io.github.agentphone.app"
OLD_DIR="io/github/eslamasabry/opencode_mobile"
NEW_DIR="io/github/agentphone/app"
OLD_DART="opencode_mobile"
NEW_DART="agentphone"

echo "== fork rename in $ROOT"

# 1. Kotlin source roots: move the package directory and rewrite the
#    package/import lines that point at it.
while IFS= read -r dir; do
  target="$(dirname "$dir")/$NEW_DIR"
  mkdir -p "$target"
  mv "$dir" "$target"
  find "$target" -type f -name "*.kt" -print0 |
    xargs -0 -r sed -i \
      -e "s/\bpackage ${OLD_PKG}\b/package ${NEW_PKG}/g" \
      -e "s/\bimport ${OLD_PKG}\./import ${NEW_PKG}./g" \
      -e "s/\b${OLD_PKG}\.${NEW_PKG}\b/${NEW_PKG}.${NEW_PKG}/g"
  echo "  moved $dir -> $target"
done < <(find "$ROOT/android" "$ROOT/integration_test" -type d -path "*/kotlin/$OLD_DIR" 2>/dev/null)

# 2. Remaining textual references to the old package name.
grep -rl "$OLD_PKG" "$ROOT/android" "$ROOT/lib" "$ROOT/test" "$ROOT/integration_test" \
  "$ROOT/tool" "$ROOT/engine" 2>/dev/null | while read -r file; do
  sed -i "s/${OLD_PKG}/${NEW_PKG}/g" "$file"
  echo "  rewrote $file"
done

# 3. Dart package name.
if [ -f "$ROOT/pubspec.yaml" ]; then
  sed -i "s/^name: ${OLD_DART}$/name: ${NEW_DART}/" "$ROOT/pubspec.yaml"
fi
grep -rl "package:${OLD_DART}/" "$ROOT/lib" "$ROOT/test" "$ROOT/integration_test" \
  "$ROOT/tool" 2>/dev/null | while read -r file; do
  sed -i "s/package:${OLD_DART}\//package:${NEW_DART}\//g" "$file"
  echo "  dart package imports in $file"
done

# 4. Deep-link scheme: the app registers its own scheme for session and team
#    hand-off links, and the manifest must match the Dart side.
grep -rl "opencode-mobile://" "$ROOT/lib" "$ROOT/android" "$ROOT/test" 2>/dev/null |
  while read -r file; do
    sed -i "s/opencode-mobile:\/\//agentphone:\/\//g" "$file"
    echo "  scheme in $file"
  done

echo "== fork rename done"
