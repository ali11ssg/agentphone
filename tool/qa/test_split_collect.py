#!/usr/bin/env python3
"""Tests for split_collect.py and gen_aggregates.py (run with unittest discover)."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

import gen_aggregates
import split_collect


def event(kind: str, time: int, **fields) -> str:
    return json.dumps({"type": kind, "time": time, **fields})


class CollectTest(unittest.TestCase):
    def report(self, root: Path, lines: list[str]) -> Path:
        path = root / "r.json"
        path.write_text("\n".join(lines) + "\n")
        return path

    def test_failures_inside_an_aggregate_map_back_to_their_file(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            shard = root / "build/agg/shard_2_test.dart"
            lines = [
                event("suite", 0, suite={"id": 0, "path": str(shard)}),
                event("testStart", 1, test={"id": 1, "name": f"loading {shard}", "suiteID": 0}),
                event("testDone", 2001, testID=1, result="success", skipped=False, hidden=True),
                event("testStart", 2002, test={"id": 2, "name": "test/a_test.dart works", "suiteID": 0}),
                event("testDone", 2502, testID=2, result="success", skipped=False, hidden=False),
                event("testStart", 2503, test={"id": 3, "name": "test/b_test.dart breaks", "suiteID": 0}),
                event("testDone", 3003, testID=3, result="failure", skipped=False, hidden=False),
                event("done", 3004, success=False),
            ]
            members = {2: ["test/a_test.dart", "test/b_test.dart"]}
            sf, af, files, agg = split_collect.collect(root, [self.report(root, lines)], members)
            self.assertEqual(sf, set())
            self.assertEqual(af, {"test/b_test.dart"})
            self.assertAlmostEqual(agg["test/a_test.dart"], 0.5)

    def test_an_entrypoint_that_does_not_load_fails_every_member(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            shard = root / "build/agg/shard_0_test.dart"
            lines = [
                event("suite", 0, suite={"id": 0, "path": str(shard)}),
                event("testStart", 1, test={"id": 1, "name": f"loading {shard}", "suiteID": 0}),
                event("testDone", 9, testID=1, result="error", skipped=False, hidden=True),
            ]
            members = {0: ["test/a_test.dart", "test/b_test.dart"]}
            _, af, _, _ = split_collect.collect(root, [self.report(root, lines)], members)
            self.assertEqual(af, set(members[0]))

    def test_a_standalone_failure_is_reported_by_path(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            lines = [
                event("suite", 0, suite={"id": 0, "path": str(root / "test/x_test.dart")}),
                event("testStart", 1, test={"id": 1, "name": "it", "suiteID": 0}),
                event("testDone", 1001, testID=1, result="failure", skipped=False, hidden=False),
            ]
            sf, af, files, _ = split_collect.collect(root, [self.report(root, lines)], {})
            self.assertEqual(sf, {"test/x_test.dart"})
            self.assertEqual(af, set())
            self.assertAlmostEqual(files["test/x_test.dart"], 1.0)


class RelativeTest(unittest.TestCase):
    def test_reports_from_the_other_machine_map_to_repo_paths(self):
        root = Path("/work/here")
        self.assertEqual(
            split_collect.relative(root, "/srv/other/checkout/test/kit/a_test.dart"),
            "test/kit/a_test.dart",
        )
        self.assertEqual(
            split_collect.relative(root, "/srv/other/checkout/build/agg/shard_3_test.dart"),
            "build/agg/shard_3_test.dart",
        )
        self.assertEqual(split_collect.relative(root, "/work/here/test/a_test.dart"), "test/a_test.dart")


class EligibleTest(unittest.TestCase):
    def test_source_rules_and_exclusion_list(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            (root / "tool/qa").mkdir(parents=True)
            (root / "tool/qa/agg_exclude.txt").write_text("test/leaky_test.dart  # leaks\n")
            (root / "test").mkdir()
            ok = "import 'a.dart';\n\nvoid main() {\n  test('x', () {});\n}\n"
            files = {
                "test/ok_test.dart": ok,
                "test/leaky_test.dart": ok,
                "test/golden_test.dart": ok + "matchesGoldenFile('x.png');",
                "test/async_test.dart": "Future<void> main() async {}\n",
                "test/binding_test.dart": ok + "class B extends AutomatedTestWidgetsFlutterBinding {}",
            }
            for name, text in files.items():
                (root / name).write_text(text)
            self.assertEqual(gen_aggregates.eligible(root, sorted(files)), ["test/ok_test.dart"])

    def test_shards_call_each_main_in_a_group_named_after_the_path(self):
        with tempfile.TemporaryDirectory() as d:
            out = Path(d)
            gen_aggregates.write_shards(out, {1: ["test/a_test.dart", "test/sub/b_test.dart"]})
            text = (out / "shard_1_test.dart").read_text()
            self.assertIn("group('test/sub/b_test.dart', t1.main);", text)
            self.assertIn("import '../../test/a_test.dart' as t0;", text)
            self.assertEqual((out / "shard_1.txt").read_text().split(), ["test/a_test.dart", "test/sub/b_test.dart"])


if __name__ == "__main__":
    unittest.main()
