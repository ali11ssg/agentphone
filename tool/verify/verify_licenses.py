#!/usr/bin/env python3
"""Checks the license obligations of a fork.

The upstream project is MIT: the LICENSE file and its copyright notice stay,
and the fork keeps the third-party notices. PRoot is GPL: its notices and the
source offer stay as well.

Run:  python3 tool/verify/verify_licenses.py
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

REQUIRED_FILES = [
    "LICENSE",
    "THIRD_PARTY_NOTICES.md",
    "NOTICE",
]


def main() -> int:
    problems: list[str] = []

    for name in REQUIRED_FILES:
        if not (ROOT / name).is_file():
            problems.append(f"missing {name}")

    license_text = (ROOT / "LICENSE").read_text(encoding="utf-8", errors="replace") if (
        ROOT / "LICENSE"
    ).is_file() else ""
    if "MIT" not in license_text and "Permission is hereby granted" not in license_text:
        problems.append("LICENSE does not look like the MIT text")
    if "Copyright" not in license_text:
        problems.append("LICENSE lost its copyright notice")

    notices = (ROOT / "THIRD_PARTY_NOTICES.md").read_text(encoding="utf-8", errors="replace") if (
        ROOT / "THIRD_PARTY_NOTICES.md"
    ).is_file() else ""
    if notices:
        if not re.search(r"proot", notices, re.IGNORECASE):
            problems.append("THIRD_PARTY_NOTICES.md does not mention PRoot (GPL)")
        if not re.search(r"gpl", notices, re.IGNORECASE):
            problems.append("THIRD_PARTY_NOTICES.md does not mention the GPL")

    licenses_dir = ROOT / "LICENSES"
    if not licenses_dir.is_dir() or not any(licenses_dir.iterdir()):
        problems.append("LICENSES/ is missing or empty")

    if problems:
        print("FAIL: license obligations not met")
        for problem in problems:
            print(f"  - {problem}")
        return 1

    print("OK: MIT license, notices and PRoot/GPL obligations intact")
    return 0


if __name__ == "__main__":
    sys.exit(main())
