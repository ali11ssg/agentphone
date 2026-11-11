#!/usr/bin/env python3
"""Tests for classify_change.py using throwaway git repositories.

Run with ``python3 -m unittest discover -s tool/qa -p 'test_classify_change.py'``.
"""

from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

import classify_change as cc


class Repo:
    def __init__(self) -> None:
        self.dir = Path(tempfile.mkdtemp())
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.email", "t@example.com")
        self.git("config", "user.name", "t")
        self.git("config", "commit.gpgsign", "false")

    def git(self, *args: str) -> str:
        return subprocess.run(
            ["git", *args], cwd=self.dir, check=True, capture_output=True, text=True
        ).stdout

    def write(self, path: str, text: str = "x\n") -> None:
        target = self.dir / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text, encoding="utf-8")

    def commit(self, message: str = "chore: step") -> None:
        self.git("add", "-A")
        self.git("commit", "-q", "-m", message)

    def classify(self) -> cc.Result:
        cwd = os.getcwd()
        os.chdir(self.dir)
        try:
            return cc.classify("base", "HEAD")
        finally:
            os.chdir(cwd)


def make_repo() -> Repo:
    repo = Repo()
    repo.write("lib/chat.dart", "a\n")
    repo.write("lib/state/store.dart", "const k = 'oc.theme';\nconst j = 'oc.old';\n")
    repo.write("lib/l10n/app_en.arb", '{\n  "hello": "Hi"\n}\n')
    repo.write("lib/domain/server_capabilities.dart", "class C {\n  final bool canFork;\n  final bool canUndo;\n}\n")
    for index in range(4):
        repo.write(f"lib/api/c{index}.dart")
    repo.write("android/app/build.gradle.kts", "minSdk = 26\n")
    repo.write("pubspec.yaml", "name: x\n")
    repo.commit("chore: base")
    repo.git("tag", "base")
    return repo


class ClassifyTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.repo = make_repo()

    def setUp(self) -> None:
        self.repo.git("checkout", "-q", "-B", "work", "base")

    def test_small_dart_change_is_hotfix(self) -> None:
        self.repo.write("lib/chat.dart", "b\n")
        self.repo.write("test/chat_test.dart")
        self.repo.commit("fix(chat): stop the crash")
        result = self.repo.classify()
        self.assertEqual(result.proposed, "hotfix")

    def test_no_change_is_hotfix_eligible(self) -> None:
        self.assertEqual(self.repo.classify().proposed, "hotfix")

    def test_native_change_is_fix_not_hotfix(self) -> None:
        self.repo.write("android/app/src/main/kotlin/Foo.kt")
        self.repo.commit("fix(android): foo")
        result = self.repo.classify()
        self.assertEqual(result.proposed, "fix")
        self.assertIn("native", result.reasons["not-hotfix"][0])

    def test_pubspec_change_is_not_hotfix(self) -> None:
        self.repo.write("pubspec.yaml", "name: y\n")
        self.repo.commit("fix(deps): bump")
        self.assertEqual(self.repo.classify().proposed, "fix")

    def test_large_dart_diff_is_fix(self) -> None:
        for index in range(cc.HOTFIX_MAX_FILES + 1):
            self.repo.write(f"lib/f{index}.dart")
        self.repo.commit("fix(chat): many files")
        self.assertEqual(self.repo.classify().proposed, "fix")

    def test_new_screen_is_feature(self) -> None:
        self.repo.write("lib/ui/screens/new_screen.dart")
        self.repo.commit("chore: screen")
        result = self.repo.classify()
        self.assertEqual(result.proposed, "feature")
        self.assertIn("new_screen.dart", result.reasons["feature"][0])

    def test_new_l10n_key_is_feature(self) -> None:
        self.repo.write("lib/l10n/app_en.arb", '{\n  "hello": "Hi",\n  "bye": "Bye"\n}\n')
        self.repo.commit("chore: copy")
        result = self.repo.classify()
        self.assertEqual(result.proposed, "feature")
        self.assertIn("bye", result.reasons["feature"][0])

    def test_new_kit_part_is_feature(self) -> None:
        self.repo.write("lib/ui/kit/kit_thing.dart")
        self.repo.commit("chore: kit")
        self.assertEqual(self.repo.classify().proposed, "feature")

    def test_removed_preference_key_is_breaking(self) -> None:
        self.repo.write("lib/state/store.dart", "const k = 'oc.theme';\n")
        self.repo.commit("fix(state): tidy")
        result = self.repo.classify()
        self.assertEqual(result.proposed, "breaking")
        self.assertIn("oc.old", result.reasons["breaking"][0])

    def test_renamed_key_counts_as_removed(self) -> None:
        self.repo.write("lib/state/store.dart", "const k = 'oc.theme';\nconst j = 'oc.newer';\n")
        self.repo.commit("fix(state): rename")
        self.assertEqual(self.repo.classify().proposed, "breaking")

    def test_new_preference_key_is_feature(self) -> None:
        self.repo.write("lib/state/store.dart", "const k = 'oc.theme';\nconst j = 'oc.old';\nconst n = 'oc.added';\n")
        self.repo.commit("chore: key")
        self.assertEqual(self.repo.classify().proposed, "feature")

    def test_removed_directory_is_breaking(self) -> None:
        self.repo.git("rm", "-q", "-r", "lib/api")
        self.repo.commit("refactor: drop the old client")
        result = self.repo.classify()
        self.assertEqual(result.proposed, "breaking")
        self.assertIn("lib/api/", result.reasons["breaking"][0])

    def test_removed_capability_is_breaking(self) -> None:
        self.repo.write("lib/domain/server_capabilities.dart", "class C {\n  final bool canFork;\n}\n")
        self.repo.commit("fix(domain): drop undo")
        result = self.repo.classify()
        self.assertEqual(result.proposed, "breaking")
        self.assertIn("canUndo", result.reasons["breaking"][0])

    def test_min_sdk_change_is_breaking(self) -> None:
        self.repo.write("android/app/build.gradle.kts", "minSdk = 28\n")
        self.repo.commit("build: raise minSdk")
        self.assertEqual(self.repo.classify().proposed, "breaking")

    def test_new_migration_file_is_breaking(self) -> None:
        self.repo.write("lib/state/profile_migration.dart")
        self.repo.commit("feat(state): migrate profiles")
        self.assertEqual(self.repo.classify().proposed, "breaking")

    def test_feat_commit_is_feature(self) -> None:
        self.repo.write("lib/chat.dart", "c\n")
        self.repo.commit("feat(chat): a thing")
        self.assertEqual(self.repo.classify().proposed, "feature")

    def test_change_class_trailer_is_read(self) -> None:
        self.repo.write("lib/chat.dart", "d\n")
        self.repo.commit("fix(chat): x\n\nChange-Class: hotfix")
        self.assertEqual(self.repo.classify().declared, ["hotfix"])


class CliTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.repo = make_repo()

    def run_cli(self, *args: str) -> subprocess.CompletedProcess[str]:
        script = Path(cc.__file__).resolve()
        return subprocess.run(
            ["python3", str(script), *args],
            cwd=self.repo.dir, capture_output=True, text=True,
        )

    def test_require_hotfix_fails_on_native(self) -> None:
        self.repo.git("checkout", "-q", "-B", "cli", "base")
        self.repo.write("android/app/src/main/kotlin/Foo.kt")
        self.repo.commit("fix(android): foo")
        ok = self.run_cli("base")
        self.assertEqual(ok.returncode, 0)
        self.assertIn("change class: fix", ok.stdout)
        self.assertIn("required gates:", ok.stdout)
        bad = self.run_cli("base", "HEAD", "--require", "hotfix")
        self.assertEqual(bad.returncode, 1)
        self.assertEqual(self.run_cli("base", "HEAD", "--require", "feature").returncode, 0)

    def test_unknown_base_exits_64(self) -> None:
        self.assertEqual(self.run_cli("nope").returncode, 64)


if __name__ == "__main__":
    unittest.main()
