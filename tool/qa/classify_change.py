#!/usr/bin/env python3
"""Propose the change class of a git range (docs/release/change-classes.md).

  tool/qa/classify_change.py <base> [<head>] [--require <class>] [--json]

Classes, smallest to largest: hotfix, fix, feature, breaking. The class is the
largest signal found in <base>...<head> (files since the merge-base) and the
commit messages in <base>..<head>. Prints the class, the reasons with paths and
the gates the class requires. Exit 0 always, unless --require <class> is given:
then exit 1 when the proposed class is larger than the required one (requiring
hotfix on a native diff, requiring fix on a feature). Exit 64 on bad input.

Only the diff is read; nothing is built, tagged or published.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from dataclasses import dataclass, field

CLASSES = ("hotfix", "fix", "feature", "breaking")
RANK = {name: index for index, name in enumerate(CLASSES)}

# A hotfix is a small, Dart-only diff.
HOTFIX_MAX_FILES = 12
HOTFIX_MAX_LINES = 300

GATES = {
    "hotfix": [
        "a repro test that fails without the fix (revert the fix, watch it fail)",
        "tool/qa/preflight.sh <release tag>",
        "full split suite (tool/qa/run_tests_fast.sh or tool/qa/run_serial_tests.py)",
        "device proof of that one fix",
        "owner OK, then scripts/release.sh patch (staging canary: docs/release/patch-canary.md)",
    ],
    "fix": [
        "tool/qa/preflight.sh <last release tag>",
        "full split suite",
        "device pass of the affected areas",
        "scripts/release.sh release|sideload (new Shorebird release, x.y.Z+N)",
    ],
    "feature": [
        "everything a fix needs",
        "real-life matrix row for each feature (docs/qa/real-life-matrix-2026-10-16/README.md)",
        "judged screenshots of each changed screen",
        "store and site text updated; two-layer notes (tool/release/release_notes.py check)",
    ],
    "breaking": [
        "everything a feature needs",
        "upgrade test from the last release on a real device",
        "migration notes; 'What changes for you' first in the release notes",
        "explicit owner sign-off",
    ],
}

NATIVE_RE = re.compile(
    r"^(android/|engine/|packages/[^/]+/android/)|\.so$|(^|/)build\.gradle(\.kts)?$"
    r"|(^|/)settings\.gradle(\.kts)?$|(^|/)gradle\.properties$|(^|/)AndroidManifest\.xml$"
)
DEPENDENCY_RE = re.compile(
    r"^(pubspec\.yaml|pubspec\.lock|shorebird\.yaml|THIRD_PARTY_NOTICES\.md)$"
    r"|^(assets|fonts|third_party|LICENSES)/"
)
CODE_ROOTS = ("lib/api/", "lib/api2/", "lib/domain/", "lib/state/", "packages/")
MIGRATION_PATH_RE = re.compile(r"(migrat|schema)", re.I)
STORE_PATH_RE = re.compile(
    r"^lib/state/(migration_runner|profile_store)[^/]*\.dart$|(^|/)[^/]*schema[^/]*\.dart$"
)
CAPABILITY_FILE_RE = re.compile(r"^lib/domain/(server_capabilities|server_flavor)[^/]*\.dart$")
CAPABILITY_REMOVED_RE = re.compile(
    r"^-\s+(?:(?:final|const)\s+[\w<>?, ]+\s+\w+\s*[;=]|this\.\w+,|[A-Za-z]\w*,\s*(?://.*)?$"
    r"|bool get \w+)"
)
PREF_KEY_RE = re.compile(r"""['"](oc\.[A-Za-z0-9_]+(?:\.[A-Za-z0-9_${}]+)*)['"]""")
GRADLE_IDENTITY_RE = re.compile(
    r"^[-+].*\b(minSdk(Version)?|applicationId|namespace|signingConfig\w*|compileSdk|targetSdk)\b"
)
L10N_KEY_RE = re.compile(r'^\+\s*"([A-Za-z][A-Za-z0-9_]*)"\s*:')
CHANGE_CLASS_RE = re.compile(r"^Change-Class:\s*(\S+)\s*$", re.M | re.I)


def git(*args: str) -> str:
    result = subprocess.run(["git", *args], capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or f"git {' '.join(args)} failed")
    return result.stdout


@dataclass
class Result:
    base: str
    head: str
    files: int = 0
    lines: int = 0
    reasons: dict[str, list[str]] = field(
        default_factory=lambda: {name: [] for name in ("not-hotfix", *CLASSES)}
    )
    declared: list[str] = field(default_factory=list)

    @property
    def proposed(self) -> str:
        if self.reasons["breaking"]:
            return "breaking"
        if self.reasons["feature"]:
            return "feature"
        if self.reasons["not-hotfix"]:
            return "fix"
        return "hotfix" if self.hotfix_eligible else "fix"

    @property
    def hotfix_eligible(self) -> bool:
        return (
            self.files <= HOTFIX_MAX_FILES
            and self.lines <= HOTFIX_MAX_LINES
            and not self.reasons["not-hotfix"]
            and not self.reasons["feature"]
            and not self.reasons["breaking"]
        )

    def add(self, kind: str, reason: str) -> None:
        if reason not in self.reasons[kind]:
            self.reasons[kind].append(reason)


def sample(paths: list[str], limit: int = 4) -> str:
    shown = ", ".join(paths[:limit])
    return shown + (f" (+{len(paths) - limit} more)" if len(paths) > limit else "")


def classify(base: str, head: str) -> Result:
    result = Result(base, head)
    status_rows = git("diff", "--name-status", "--no-renames", f"{base}...{head}").splitlines()
    added: list[str] = []
    deleted: list[str] = []
    modified: list[str] = []
    for row in status_rows:
        code, _, path = row.partition("\t")
        {"A": added, "D": deleted}.get(code[:1], modified).append(path)
    everything = added + deleted + modified
    result.files = len(everything)
    for row in git("diff", "--numstat", "--no-renames", f"{base}...{head}").splitlines():
        a, _, rest = row.partition("\t")
        d = rest.partition("\t")[0]
        result.lines += (int(a) if a.isdigit() else 0) + (int(d) if d.isdigit() else 0)

    # Not hotfix: native code, dependencies, bundled assets.
    native = [p for p in everything if NATIVE_RE.search(p)]
    if native:
        result.add("not-hotfix", f"native inputs change: {sample(native)}")
    dependencies = [p for p in everything if DEPENDENCY_RE.search(p)]
    if dependencies:
        result.add("not-hotfix", f"pubspec, assets or third-party inputs change: {sample(dependencies)}")
    non_dart = [p for p in everything if p.startswith("lib/") and not p.endswith(".dart")
                and not p.startswith("lib/l10n/")]
    if non_dart:
        result.add("not-hotfix", f"non-Dart files under lib/: {sample(non_dart)}")
    if result.files > HOTFIX_MAX_FILES or result.lines > HOTFIX_MAX_LINES:
        result.add(
            "not-hotfix",
            f"diff too large for a hotfix ({result.files} files, {result.lines} lines; "
            f"limit {HOTFIX_MAX_FILES} files, {HOTFIX_MAX_LINES} lines)",
        )

    # Breaking: stored data, migrations, removed capabilities, identity.
    for root in CODE_ROOTS:
        gone = [p for p in deleted if p.startswith(root)]
        if not gone:
            continue
        tree_left = git("ls-tree", "-r", "--name-only", head, "--", root).strip()
        if not tree_left:
            result.add("breaking", f"{root} removed entirely ({len(gone)} files)")
        elif len(gone) >= 3 and root != "lib/state/":
            result.add("breaking", f"{len(gone)} files deleted under {root}: {sample(gone)}")
    migration_files = [
        p for p in added + deleted
        if p.startswith("lib/") and MIGRATION_PATH_RE.search(p) and p.endswith(".dart")
    ]
    if migration_files:
        result.add("breaking", f"migration or schema code added/removed: {sample(migration_files)}")
    store_files = [p for p in modified if STORE_PATH_RE.search(p)]
    if store_files:
        result.add("breaking", f"stored-data format code changes: {sample(store_files)}")

    lib_diff = git("diff", "-U0", "--no-renames", f"{base}...{head}", "--", "lib/*.dart")
    removed_keys: set[str] = set()
    added_keys: set[str] = set()
    for line in lib_diff.splitlines():
        if line.startswith(("+++", "---")):
            continue
        keys = PREF_KEY_RE.findall(line)
        if line.startswith("-"):
            removed_keys.update(keys)
        elif line.startswith("+"):
            added_keys.update(keys)
    gone_keys = sorted(removed_keys - added_keys)
    new_keys = sorted(added_keys - removed_keys)
    if gone_keys:
        result.add("breaking", f"stored 'oc.' preference keys removed: {sample(gone_keys, 6)}")
    if new_keys:
        result.add("feature", f"new stored 'oc.' preference keys (check whether old data needs a migration): {sample(new_keys, 6)}")

    capability_files = [p for p in modified + deleted if CAPABILITY_FILE_RE.search(p)]
    for path in capability_files:
        diff = git("diff", "-U0", "--no-renames", f"{base}...{head}", "--", path)
        plus = {l[1:].strip() for l in diff.splitlines() if l.startswith("+") and not l.startswith("+++")}
        dropped = [
            l[1:].strip() for l in diff.splitlines()
            if CAPABILITY_REMOVED_RE.match(l) and l[1:].strip() not in plus
        ]
        if path in deleted:
            dropped = ["(file deleted)"]
        if dropped:
            result.add("breaking", f"capability or flavor removed in {path}: {sample(dropped, 3)}")

    gradle = [p for p in modified + added if re.search(r"(^|/)build\.gradle(\.kts)?$", p)]
    for path in gradle:
        diff = git("diff", "-U0", "--no-renames", f"{base}...{head}", "--", path)
        hits = [l.strip() for l in diff.splitlines() if GRADLE_IDENTITY_RE.match(l)]
        if hits:
            result.add("breaking", f"minSdk, package or signing identity changes in {path}: {sample(hits, 3)}")
    manifest_ids = [p for p in modified if p.endswith("AndroidManifest.xml")]
    for path in manifest_ids:
        diff = git("diff", "-U0", "--no-renames", f"{base}...{head}", "--", path)
        if re.search(r'^[-+].*\bpackage=', diff, re.M):
            result.add("breaking", f"manifest package changes in {path}")

    # Feature: new screens, new copy keys, new kit parts.
    screens = [p for p in added if re.match(r"^lib/ui/screens/.+\.dart$", p)]
    if screens:
        result.add("feature", f"new screen files: {sample(screens)}")
    kit = [p for p in added if re.match(r"^lib/ui/kit/.+\.dart$", p)]
    if kit:
        result.add("feature", f"new kit parts: {sample(kit)}")
    arb = git("diff", "-U0", "--no-renames", f"{base}...{head}", "--", "lib/l10n/app_en.arb")
    new_l10n = [m.group(1) for l in arb.splitlines() if (m := L10N_KEY_RE.match(l))]
    removed_l10n = {
        m.group(1) for l in arb.splitlines()
        if l.startswith("-") and (m := re.match(r'^-\s*"([A-Za-z]\w*)"\s*:', l))
    }
    new_l10n = [k for k in new_l10n if k not in removed_l10n]
    if new_l10n:
        result.add("feature", f"{len(new_l10n)} new l10n keys: {sample(new_l10n, 5)}")

    # Commit messages.
    log = git("log", "--format=%H%x1f%s%x1f%B%x1e", f"{base}..{head}")
    feat = 0
    for record in log.split("\x1e"):
        parts = record.strip("\n").split("\x1f")
        if len(parts) < 3:
            continue
        if re.match(r"^feat(\([^)]*\))?!?:", parts[1]):
            feat += 1
        if re.match(r"^[a-z]+(\([^)]*\))?!:", parts[1]):
            result.add("breaking", f"breaking marker in commit subject: {parts[1][:70]}")
        for value in CHANGE_CLASS_RE.findall(parts[2]):
            if value.lower() in RANK and value.lower() not in result.declared:
                result.declared.append(value.lower())
    if feat:
        result.add("feature", f"{feat} feat commit(s) in the range")
    return result


def render(result: Result) -> str:
    proposed = result.proposed
    lines = [
        f"change class: {proposed}",
        f"range: {result.base}...{result.head} ({result.files} files, {result.lines} changed lines)",
    ]
    order = ["breaking", "feature", "not-hotfix"]
    titles = {"breaking": "breaking", "feature": "feature", "not-hotfix": "not a hotfix"}
    for kind in order:
        if result.reasons[kind]:
            lines.append(f"{titles[kind]}:")
            lines.extend(f"  - {r}" for r in result.reasons[kind])
    if proposed == "hotfix":
        lines.append(f"hotfix-eligible: Dart-only, {result.files} files, {result.lines} lines")
    if proposed == "fix" and not result.reasons["not-hotfix"]:
        lines.append("no feature, breaking or native signal found")
    if result.declared:
        note = "declared by Change-Class trailers: " + ", ".join(result.declared)
        if any(RANK[c] < RANK[proposed] for c in result.declared):
            note += f" (the diff looks larger: {proposed})"
        lines.append(note)
    lines.append("required gates:")
    lines.extend(f"  - {g}" for g in GATES[proposed])
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("base")
    parser.add_argument("head", nargs="?", default="HEAD")
    parser.add_argument("--require", choices=CLASSES)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)
    try:
        result = classify(args.base, args.head)
    except RuntimeError as error:
        print(f"classify_change: {error}", file=sys.stderr)
        return 64
    if args.json:
        print(json.dumps({
            "class": result.proposed, "files": result.files, "lines": result.lines,
            "reasons": result.reasons, "declared": result.declared,
        }))
    else:
        print(render(result))
    if args.require and RANK[result.proposed] > RANK[args.require]:
        print(
            f"classify_change: required {args.require} but the range is {result.proposed}",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
