#!/usr/bin/env python3
"""Tests for split_plan.py (run: python3 -m unittest discover -s tool/qa -p 'test_*.py')."""

from __future__ import annotations

import unittest

import split_plan


class SplitPlanTest(unittest.TestCase):
    def test_every_file_lands_on_exactly_one_machine(self):
        files = [f"test/f{i}_test.dart" for i in range(40)]
        weights = {f: float(i + 1) for i, f in enumerate(files)}
        local, remote, _, _ = split_plan.plan(files, weights, 3, 6, 0.33)
        self.assertEqual(sorted(local + remote), sorted(files))
        self.assertFalse(set(local) & set(remote))

    def test_slow_machine_gets_less_work(self):
        files = [f"test/f{i}_test.dart" for i in range(200)]
        weights = {f: 2.0 for f in files}
        local, remote, ls, rs = split_plan.plan(files, weights, 3, 6, 0.33)
        self.assertGreater(len(local), len(remote) * 0.9)
        self.assertLess(abs(ls - rs), 6.0)

    def test_longest_file_goes_to_the_fast_machine(self):
        files = ["test/long_test.dart"] + [f"test/s{i}_test.dart" for i in range(10)]
        weights = {f: 1.0 for f in files}
        weights["test/long_test.dart"] = 200.0
        local, _, _, _ = split_plan.plan(files, weights, 3, 6, 0.33)
        self.assertIn("test/long_test.dart", local)

    def test_unknown_files_weigh_the_median(self):
        files = ["test/a_test.dart", "test/b_test.dart", "test/new_test.dart"]
        local, remote, _, _ = split_plan.plan(
            files, {"test/a_test.dart": 4.0, "test/b_test.dart": 4.0}, 1, 0, 1.0
        )
        self.assertEqual(len(local), 3)
        self.assertEqual(remote, [])

    def test_bundled_files_are_placed_as_one_unit_each_file_once(self):
        files = [f"test/f{i}_test.dart" for i in range(60)] + ["test/big_test.dart"]
        weights = {f: 5.0 for f in files}
        weights["test/big_test.dart"] = 100.0
        pool = [f for f in files if f != "test/big_test.dart"]
        bundles, seconds = split_plan.make_bundles(pool, weights, {}, 4)
        self.assertEqual(sorted(f for m in bundles.values() for f in m), sorted(pool))
        local, remote, _, _ = split_plan.plan(files, weights, 3, 6, 0.33, bundles, seconds)
        self.assertEqual(sorted(local + remote), sorted(files))
        units = split_plan.plan.last_units
        placed = [u for us in units.values() for u in us if u[0] == "A"]
        self.assertEqual(sorted(i for _, i in placed), sorted(bundles))


if __name__ == "__main__":
    unittest.main()
