#!/usr/bin/env python3
"""Runs every pre-push gate. Any failure blocks the push.

    python3 tool/verify/verify_all.py

Checks:
  1. manifest permissions stay inside the allowed list
  2. no analytics, crash reporting or telemetry code remains
  3. no secrets or key material in tracked files
  4. license, notices and PRoot/GPL obligations intact
  5. no Shorebird leftovers (the fork builds with stable Flutter)
  6. the app id differs from the upstream project (both can be installed)
  7. Dart sources are formatted (skipped when no Dart SDK is present)
"""
from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent

UPSTREAM_APPLICATION_ID = "io.github.eslamasabry.opencode_mobile"


def run_script(name: str) -> tuple[int, str]:
    result = subprocess.run(
        [sys.executable, str(HERE / name)],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    return result.returncode, (result.stdout + result.stderr).strip()


def check_no_shorebird() -> tuple[int, str]:
    hits: list[str] = []
    pubspec = ROOT / "pubspec.yaml"
    if pubspec.is_file() and "shorebird" in pubspec.read_text(encoding="utf-8", errors="replace").lower():
        hits.append("pubspec.yaml still depends on Shorebird")
    workflows = ROOT / ".github" / "workflows"
    if workflows.is_dir():
        for path in sorted(workflows.glob("*.y*ml")):
            if "shorebird" in path.read_text(encoding="utf-8", errors="replace").lower():
                hits.append(f"{path.relative_to(ROOT)} still uses Shorebird")
    if hits:
        return 1, "FAIL: Shorebird leftovers\n  - " + "\n  - ".join(hits)
    return 0, "OK: no Shorebird leftovers"


def check_application_id() -> tuple[int, str]:
    gradle = ROOT / "android" / "app" / "build.gradle.kts"
    if not gradle.is_file():
        return 1, "FAIL: android/app/build.gradle.kts not found"
    text = gradle.read_text(encoding="utf-8", errors="replace")
    match = re_search_application_id(text)
    if not match:
        return 1, "FAIL: no applicationId in build.gradle.kts"
    if match == UPSTREAM_APPLICATION_ID:
        return 1, f"FAIL: applicationId is still the upstream id ({match})"
    return 0, f"OK: applicationId is {match}"


def re_search_application_id(text: str) -> str | None:
    import re

    match = re.search(r'applicationId\s*=\s*"([^"]+)"', text)
    return match.group(1) if match else None


def check_format() -> tuple[int, str]:
    if shutil.which("dart") is None:
        return 0, "SKIP: no Dart SDK on this machine (format is checked in CI)"
    result = subprocess.run(
        ["dart", "format", "--output=none", "--set-exit-if-changed", "lib", "test"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        return 1, "FAIL: dart format found unformatted files\n" + (result.stdout + result.stderr)[-2000:]
    return 0, "OK: dart format clean"


def main() -> int:
    results: list[tuple[str, int, str]] = []

    for script in [
        "verify_permissions.py",
        "verify_no_analytics.py",
        "verify_no_secrets.py",
        "verify_licenses.py",
    ]:
        code, output = run_script(script)
        results.append((script, code, output))

    for name, checker in [("no-shorebird", check_no_shorebird), ("application-id", check_application_id), ("format", check_format)]:
        code, output = checker()
        results.append((name, code, output))

    failed = 0
    for name, code, output in results:
        status = "OK  " if code == 0 else "FAIL"
        print(f"[{status}] {name}")
        for line in output.splitlines():
            print(f"       {line}")
        if code != 0:
            failed += 1

    print()
    if failed:
        print(f"{failed} gate(s) failed")
        return 1
    print("all gates passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
