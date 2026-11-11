#!/usr/bin/env python3
"""Fails when analytics, crash reporting or telemetry code remains.

AgentPhone ships no analytics and no telemetry: the user talks only to servers
they configure. The check covers source, build files and the manifest; prose in
documentation is reported as a warning only.

Run:  python3 tool/verify/verify_no_analytics.py
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

# Whole words only: "webSourcesEntryDetail" contains "sentry" as a substring,
# and that is not a crash-reporting vendor.
FORBIDDEN = [
    r"firebase_core",
    r"firebase_crashlytics",
    r"firebase_analytics",
    r"firebase_performance",
    r"google-services",
    r"\bcrashlytics\b",
    r"package:firebase",
    r"com\.google\.firebase",
    r"google_analytics",
    r"\bGoogleAnalytics\b",
    r"\bamplitude\b",
    r"\bmixpanel\b",
    r"\bbugsnag\b",
    r"\bdatadog\b",
    r"\bappcenter\b",
]

# Names that are only a vendor when they appear in a dependency file: in
# ordinary code "sentry" is a word a test fixture may use for a fake
# connector name.
VENDOR_ONLY_IN_DEPS = [
    r"\bsentry\b",
    r"\bamplitude\b",
    r"\bmixpanel\b",
    r"\badjust_sdk\b",
    r"branch_sdk",
]

CODE_DIRS = ["lib", "android", "ios", "macos", "web", "windows", "linux", "tool", "scripts"]
CODE_FILES = ["pubspec.yaml", "Podfile", "analysis_options.yaml"]
# Dependency files: a vendor name here means the vendor is really wired in.
DEPENDENCY_FILES = [
    "pubspec.yaml",
    "pubspec.lock",
    "android/settings.gradle.kts",
    "android/build.gradle.kts",
    "android/app/build.gradle.kts",
    "android/app/src/main/AndroidManifest.xml",
    "Podfile",
    "package.json",
]
DOC_DIRS = ["docs", "test", "integration_test"]

SKIP_SUFFIXES = {".md", ".png", ".jpg", ".jpeg", ".webp", ".ico", ".ttf", ".otf", ".bin", ".so"}
MAX_TEXT_BYTES = 2 * 1024 * 1024


def iter_dependency_files() -> list[Path]:
    files: list[Path] = []
    for name in DEPENDENCY_FILES:
        path = ROOT / name
        if path.is_file():
            files.append(path)
    return files


def iter_files() -> list[Path]:
    files: list[Path] = []
    for name in CODE_FILES:
        path = ROOT / name
        if path.is_file():
            files.append(path)
    for directory in CODE_DIRS:
        base = ROOT / directory
        if not base.is_dir():
            continue
        for path in base.rglob("*"):
            if not path.is_file():
                continue
            if path.suffix.lower() in SKIP_SUFFIXES:
                continue
            if any(part in {"build", ".dart_tool", ".git"} for part in path.parts):
                continue
            files.append(path)
    return files


def main() -> int:
    errors: list[str] = []
    warnings: list[str] = []

    for path in iter_files():
        try:
            if path.stat().st_size > MAX_TEXT_BYTES:
                continue
            raw = path.read_bytes()
        except OSError:
            continue
        if b"\0" in raw[:4096]:
            continue  # binary
        text = raw.decode("utf-8", errors="replace")
        lowered = text.lower()
        for needle in FORBIDDEN:
            if not re.search(needle, lowered):
                continue
            relative = path.relative_to(ROOT)
            if relative.parts[:2] == ("tool", "verify"):
                continue  # this gate names the vendors it looks for
            if "testlab" in relative.name:
                # Google's cloud device farm CLI, not app telemetry.
                continue
            if relative.parts[:2] == ("tool", "branding"):
                continue  # the copy fixer names the strings it replaces
            if relative.name == "audit_apk.sh":
                continue  # an audit that bans the vendor on purpose
            if any(part in DOC_DIRS for part in relative.parts):
                warnings.append(f"{relative}: mentions '{needle}' (documentation)")
            else:
                errors.append(f"{relative}: contains '{needle}'")

    if warnings:
        print("WARN: documentation mentions (not code):")
        for warning in warnings[:20]:
            print(f"  - {warning}")
        if len(warnings) > 20:
            print(f"  ... and {len(warnings) - 20} more")

    for path in iter_dependency_files():
        try:
            text = path.read_text(encoding="utf-8", errors="replace").lower()
        except OSError:
            continue
        relative = path.relative_to(ROOT)
        for needle in VENDOR_ONLY_IN_DEPS:
            if re.search(needle, text):
                errors.append(f"{relative}: dependency file mentions '{needle}'")

    if errors:
        print("FAIL: analytics/telemetry code still present")
        for error in errors:
            print(f"  - {error}")
        return 1

    print("OK: no analytics, crash reporting or telemetry in code")
    return 0


if __name__ == "__main__":
    sys.exit(main())
