#!/usr/bin/env python3
"""Tests for the two-layer release notes tool.

Run with ``python3 -m unittest discover -s tool/release -p 'test_*.py'``.
No Git repository or network is touched: notes are written to temp files.
"""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import release_notes as notes

GOOD = """# AgentPhone 1.3.0+53

Agents that need a sign-in say so.

## What changed for you

<!-- guidance for the writer, ignored -->

- **Codex, Gemini CLI and Qwen Code** say when they need you to sign in,
  instead of "Checking sign-in…" forever (thanks, #95).
- The welcome recommends **On this phone** when you have no server.

## Technical changes

### Fixed
- Phone agents report a sign-in state after a re-read.
"""


class CheckTest(unittest.TestCase):
    def write(self, text: str, name: str = "v1.3.0+53.md") -> Path:
        folder = Path(tempfile.mkdtemp())
        path = folder / name
        path.write_text(text, encoding="utf-8")
        return path

    def test_two_layers_in_order_pass(self) -> None:
        self.assertEqual(notes.check(self.write(GOOD)), [])

    def test_wrapped_bullet_is_one_bullet(self) -> None:
        parsed = notes.parse(GOOD)
        self.assertEqual(len(parsed.user), 2)
        self.assertIn("forever (thanks, #95)", parsed.user[0])

    def test_missing_user_layer_fails(self) -> None:
        text = GOOD.replace("## What changed for you", "## Highlights")
        problems = notes.check(self.write(text))
        self.assertTrue(any("missing '## What changed for you'" in p for p in problems))

    def test_technical_first_fails(self) -> None:
        user = GOOD[GOOD.index("## What changed") : GOOD.index("## Technical")]
        tech = GOOD[GOOD.index("## Technical") :]
        text = "# AgentPhone 1.3.0+53\n\n" + tech + "\n" + user
        problems = notes.check(self.write(text))
        self.assertTrue(any("must come before" in p for p in problems))

    def test_wrong_title_fails(self) -> None:
        text = GOOD.replace("1.3.0+53", "1.3.0+54", 1)
        problems = notes.check(self.write(text))
        self.assertTrue(any("first line" in p for p in problems))

    def test_internal_words_and_code_fail(self) -> None:
        text = GOOD.replace(
            "- The welcome recommends",
            "- Refactor the `ConnectionController` in lib/state/connection.dart.\n"
            "- The welcome recommends",
        )
        problems = notes.check(self.write(text))
        joined = "\n".join(problems)
        self.assertIn("internal word 'refactor'", joined)
        self.assertIn("backticks", joined)
        self.assertIn("a file name", joined)

    def test_too_many_bullets_fail(self) -> None:
        extra = "".join(f"- Thing {i} works.\n" for i in range(5))
        text = GOOD.replace("## Technical changes", extra + "\n## Technical changes")
        problems = notes.check(self.write(text))
        self.assertTrue(any("2 to 5 bullets" in p for p in problems))

    def test_store_length_limit(self) -> None:
        long = "- " + "Words that keep going. " * 30 + "\n"
        text = GOOD.replace("## Technical changes", long + "\n## Technical changes")
        problems = notes.check(self.write(text))
        self.assertTrue(any("store changelog" in p for p in problems))

    def test_template_placeholders_fail(self) -> None:
        problems = notes.check(self.write(notes.TEMPLATE.read_text(encoding="utf-8")))
        joined = "\n".join(problems)
        self.assertIn("placeholder", joined)

    def test_shipped_template_has_both_layers_in_order(self) -> None:
        parsed = notes.parse(notes.TEMPLATE.read_text(encoding="utf-8"))
        self.assertGreaterEqual(parsed.user_index, 0)
        self.assertGreater(parsed.tech_index, parsed.user_index)


class ChangeClassTest(unittest.TestCase):
    def write(self, line: str) -> Path:
        folder = Path(tempfile.mkdtemp())
        path = folder / "v1.3.0+53.md"
        path.write_text(
            GOOD.replace("\nAgents that need", f"\n{line}\nAgents that need", 1),
            encoding="utf-8",
        )
        return path

    def test_class_line_is_optional(self) -> None:
        self.assertIsNone(notes.parse(GOOD).change_class)
        self.assertEqual(notes.check(self.write("Change class: feature")), [])

    def test_unknown_class_fails(self) -> None:
        problems = notes.check(self.write("Change class: huge"))
        self.assertTrue(any("Change class" in p for p in problems))

    def test_mismatch_warns_only(self) -> None:
        path = self.write("Change class: hotfix")
        original = (notes.previous_tag, notes.subprocess.run)

        class Run:
            returncode = 0
            stdout = '{"class": "breaking"}'

        try:
            notes.previous_tag = lambda own: "v1.2.0+52"
            notes.subprocess.run = lambda *a, **k: Run()
            warnings = notes.class_warnings(path)
        finally:
            notes.previous_tag, notes.subprocess.run = original
        self.assertEqual(len(warnings), 1)
        self.assertIn("breaking", warnings[0])
        self.assertEqual(notes.check(path), [])


class StoreTextTest(unittest.TestCase):
    def test_plain_words_without_markdown(self) -> None:
        text = notes.store_text(notes.parse(GOOD))
        self.assertTrue(text.startswith("• Codex, Gemini CLI and Qwen Code say"))
        self.assertNotIn("**", text)
        self.assertNotIn("guidance", text)
        self.assertEqual(text.count("•"), 2)


class DraftTest(unittest.TestCase):
    def test_conventional_commits_group_under_headings(self) -> None:
        groups = notes.draft_technical(
            [
                "feat(welcome): the phone choice leads as Recommended [skip ci]",
                "fix(agents): a re-read keeps the last sign-in answer [skip ci]",
                "perf(chat): open faster",
                "docs(readme): new first screen [skip ci]",
                "merge: fix/smooth-drawing",
                "fix(agents): a re-read keeps the last sign-in answer [skip ci]",
            ]
        )
        self.assertEqual(groups["Added"], ["The phone choice leads as Recommended"])
        self.assertEqual(groups["Fixed"], ["A re-read keeps the last sign-in answer"])
        self.assertEqual(groups["Changed"], ["Open faster"])

    def test_render_new_fills_lists_and_version(self) -> None:
        text = notes.render_new(
            "1.3.0+53",
            notes.TEMPLATE.read_text(encoding="utf-8"),
            {"Added": ["A thing"], "Changed": [], "Fixed": ["A bug"]},
        )
        self.assertTrue(text.startswith("# AgentPhone 1.3.0+53\n"))
        self.assertIn("### Added\n- A thing", text)
        self.assertIn("### Fixed\n- A bug", text)
        # Empty groups keep the placeholder, so check fails until edited.
        self.assertIn("### Changed\n- …", text)


if __name__ == "__main__":
    unittest.main()
