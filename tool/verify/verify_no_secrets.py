#!/usr/bin/env python3
"""Fails when a secret is committed or when key material sits in the tree.

Real API keys must never reach the repository, the Linux environment inside the
app, or a log file. Keystores live outside the repository (see keystore/, which
is git-ignored) and are uploaded to GitHub Secrets.

Run:  python3 tool/verify/verify_no_secrets.py
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

# High-confidence secret shapes. Test fixtures are allowed to contain obvious
# dummies, so those directories are reported as warnings instead of failures.
PATTERNS: list[tuple[str, re.Pattern[str]]] = [
    ("OpenAI key", re.compile(r"\bsk-[A-Za-z0-9_-]{20,}\b")),
    ("Anthropic key", re.compile(r"\bsk-ant-[A-Za-z0-9_-]{20,}\b")),
    ("GitHub token", re.compile(r"\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{30,}\b")),
    ("GitHub fine-grained token", re.compile(r"\bgithub_pat_[A-Za-z0-9_]{20,}\b")),
    ("AWS access key id", re.compile(r"\bAKIA[0-9A-Z]{16}\b")),
    ("Slack token", re.compile(r"\bxox[abprs]-[A-Za-z0-9-]{10,}\b")),
    ("Google API key", re.compile(r"\bAIza[0-9A-Za-z_-]{35}\b")),
    ("Private key block", re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH |PGP )?PRIVATE KEY-----")),
    ("Bearer token literal", re.compile(r"\bBearer\s+[A-Za-z0-9._-]{40,}\b")),
    ("Generic assignment", re.compile(
        r"""(?i)\b(?:api[_-]?key|secret|password|passwd|token)\s*[:=]\s*['\"][^'\"\s]{16,}['\"]""")),
]

# A test fixture holds obvious dummies. These markers say so, and a value that
# carries one of them is not a secret.
PLACEHOLDER_MARKERS = (
    "test",
    "fake",
    "dummy",
    "example",
    "sample",
    "placeholder",
    "redacted",
    "xxxx",
    "notreal",
    "your-",
    "<",
)

KEY_SUFFIXES = {".p12", ".pfx", ".jks", ".keystore", ".pem", ".key", ".p8", ".der"}
# Text files only: a binary blob is not a place a secret is written, and
# reading megabytes of native libraries on a phone is slow.
MAX_TEXT_BYTES = 2 * 1024 * 1024
ALLOWED_DIRS = {"test", "integration_test", "tool/verify/fixtures"}
# Directories whose files are fixtures and probes by nature.
TOOLING_PREFIXES = ("tool/",)
SKIP_DIRS = {".git", "build", ".dart_tool", ".idea", "node_modules"}


def tracked_files() -> list[Path]:
    try:
        result = subprocess.run(
            ["git", "ls-files", "-z"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=60,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return []
    if result.returncode != 0:
        return []
    return [ROOT / name for name in result.stdout.split("\0") if name]


def main() -> int:
    files = tracked_files()
    if not files:
        print("WARN: git ls-files returned nothing; scanning the working tree instead")
        files = [
            path
            for path in ROOT.rglob("*")
            if path.is_file()
            and not any(part in SKIP_DIRS for part in path.relative_to(ROOT).parts)
        ]

    errors: list[str] = []
    warnings: list[str] = []

    for path in files:
        relative = path.relative_to(ROOT)
        if any(part in SKIP_DIRS for part in relative.parts):
            continue
        if relative.suffix.lower() in KEY_SUFFIXES:
            errors.append(f"{relative}: key material committed to the repository")
            continue
        try:
            if path.stat().st_size > MAX_TEXT_BYTES:
                continue
            raw = path.read_bytes()
        except OSError:
            continue
        if b"\0" in raw[:4096]:
            continue  # binary
        text = raw.decode("utf-8", errors="replace")
        for label, pattern in PATTERNS:
            match = pattern.search(text)
            if not match:
                continue
            if label == "Generic assignment":
                value = match.group(0).lower()
                if any(marker in value for marker in PLACEHOLDER_MARKERS):
                    continue
            message = f"{relative}: looks like {label}"
            if any(str(relative).startswith(prefix) for prefix in ALLOWED_DIRS) or str(relative).startswith(TOOLING_PREFIXES):
                warnings.append(message + " (test fixture)")
            else:
                errors.append(message)

    for warning in warnings:
        print(f"WARN: {warning}")

    if errors:
        print("FAIL: secrets or key material found")
        for error in errors:
            print(f"  - {error}")
        return 1

    print("OK: no secrets or key material in tracked files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
