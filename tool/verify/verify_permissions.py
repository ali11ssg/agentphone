#!/usr/bin/env python3
"""Fails when the Android manifest declares a permission outside the allowed list.

The list is deliberately small: AgentPhone only needs the network, notifications,
a foreground service, a wake lock, battery-optimization exemption and biometrics.

Run:  python3 tool/verify/verify_permissions.py
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

ALLOWED = {
    "android.permission.INTERNET",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.FOREGROUND_SERVICE",
    # Type-specific foreground service permissions: they are part of the
    # "correct type" requirement for FOREGROUND_SERVICE.
    "android.permission.FOREGROUND_SERVICE_SPECIAL_USE",
    "android.permission.FOREGROUND_SERVICE_DATA_SYNC",
    "android.permission.WAKE_LOCK",
    "android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS",
    "android.permission.USE_BIOMETRIC",
}

# Plugins whose own manifest injects a permission we do not want.
FORBIDDEN_PLUGIN_HINTS = {
    "camera": "android.permission.CAMERA",
    "record": "android.permission.RECORD_AUDIO",
    "mobile_scanner": "android.permission.CAMERA",
    "flutter_local_notifications": None,
}


def manifest_permissions(path: Path) -> list[str]:
    text = path.read_text(encoding="utf-8", errors="replace")
    return re.findall(
        r'<uses-permission[^>]*android:name="([^"]+)"', text
    ) + re.findall(r'<uses-permission[^>]*android:name="([^"]+)"', text)


def pubspec_deps(path: Path) -> set[str]:
    names: set[str] = set()
    in_deps = False
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith("dependencies:"):
            in_deps = True
            continue
        if in_deps and line and not line[0].isspace():
            break
        if in_deps:
            m = re.match(r"^  ([a-z0-9_]+):", line)
            if m:
                names.add(m.group(1))
    return names


def main() -> int:
    manifest = ROOT / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
    if not manifest.exists():
        print(f"FAIL: manifest not found: {manifest}")
        return 1

    found = sorted(set(manifest_permissions(manifest)))
    # tools:node="remove" entries are declarations that cancel a plugin
    # permission; they must not appear in the merged manifest, so they are
    # still treated as declared and therefore reported.
    problems: list[str] = []
    for permission in found:
        if permission not in ALLOWED:
            problems.append(f"manifest declares {permission}")

    deps = pubspec_deps(ROOT / "pubspec.yaml")
    for plugin, permission in FORBIDDEN_PLUGIN_HINTS.items():
        if plugin in deps and permission:
            problems.append(
                f"pubspec depends on '{plugin}' which injects {permission}"
            )

    if problems:
        print("FAIL: permissions outside the allowed list")
        for problem in problems:
            print(f"  - {problem}")
        print("allowed:")
        for permission in sorted(ALLOWED):
            print(f"  - {permission}")
        return 1

    print(f"OK: permissions limited to {len(ALLOWED)} allowed entries")
    return 0


if __name__ == "__main__":
    sys.exit(main())
