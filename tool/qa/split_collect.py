#!/usr/bin/env python3
"""Read `flutter test --file-reporter json:` reports of a split run.

    split_collect.py --root R --plan PLAN [--plan PLAN ...] --out DIR
                     [--scale S --merge-into TIMINGS.json] REPORT [REPORT ...]

Writes in DIR:
  standalone-failed.txt  test files that ran alone and failed
  agg-failed.txt         test files that failed inside an aggregated entrypoint
                         (every member when the entrypoint itself did not load);
                         run_tests_split.sh runs each of them alone before it counts
  timings.json           {"files": {file: seconds}, "agg": {file: seconds}} measured now

A report without its final "done" event (the run was cut short) is listed in
DIR/incomplete.txt. With --merge-into, the measured seconds times --scale (a
slower machine's seconds times its relative speed) overwrite those files'
entries in TIMINGS.json, which tool/qa/split_plan.py reads.

PLAN files are the "F <file>" / "A <bundle> <file>" lists written by
split_plan.py; they say which files belong to which entrypoint
(build/agg/shard_<bundle>_test.dart).
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

SHARD = re.compile(r"(?:^|/)build/agg/shard_(\d+)_test\.dart$")


def read_plans(paths: list[Path]) -> dict[int, list[str]]:
    members: dict[int, list[str]] = {}
    for p in paths:
        for line in p.read_text().splitlines():
            parts = line.split()
            if len(parts) == 3 and parts[0] == "A":
                members.setdefault(int(parts[1]), []).append(parts[2])
    return members


def relative(root: Path, path: str) -> str:
    """The repo-relative path of a suite; reports from the server hold its own absolute paths."""
    try:
        return str(Path(path).resolve().relative_to(root.resolve()))
    except ValueError:
        pass
    for marker in ("/build/agg/", "/test/"):
        at = path.find(marker)
        if at >= 0:
            return path[at + 1 :]
    return path


def collect(root: Path, reports: list[Path], members: dict[int, list[str]]):
    standalone_failed: set[str] = set()
    agg_failed: set[str] = set()
    files: dict[str, float] = {}
    agg: dict[str, float] = {}
    for report in reports:
        suites: dict[int, str] = {}
        starts: dict[int, tuple[int, str, int]] = {}  # test id -> (suite, name, ms)
        for raw in report.read_text(errors="replace").splitlines():
            try:
                ev = json.loads(raw)
            except ValueError:
                continue
            kind = ev.get("type")
            if kind == "suite":
                suites[ev["suite"]["id"]] = ev["suite"]["path"]
            elif kind == "testStart":
                t = ev["test"]
                starts[t["id"]] = (t["suiteID"], t["name"], ev["time"])
            elif kind == "testDone":
                begin = starts.get(ev["testID"])
                if begin is None:
                    continue
                sid, name, t0 = begin
                path = suites.get(sid, "")
                rel = relative(root, path)
                seconds = max(0, ev["time"] - t0) / 1000.0
                failed = ev.get("result") in ("failure", "error") and not ev.get("skipped")
                shard = SHARD.search(rel)
                if shard:
                    if name.startswith("loading "):
                        if failed:
                            agg_failed.update(members.get(int(shard.group(1)), []))
                        continue
                    source = name.split(" ", 1)[0]
                    if not source.endswith("_test.dart"):
                        continue
                    agg[source] = agg.get(source, 0.0) + seconds
                    if failed:
                        agg_failed.add(source)
                else:
                    files[rel] = files.get(rel, 0.0) + seconds
                    if failed:
                        standalone_failed.add(rel)
    return standalone_failed, agg_failed, files, agg


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--root", type=Path, default=Path("."))
    ap.add_argument("--plan", type=Path, action="append", default=[])
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--scale", type=float, default=1.0)
    ap.add_argument("--merge-into", type=Path)
    ap.add_argument("reports", nargs="+", type=Path)
    a = ap.parse_args()
    reports = [r for r in a.reports if r.is_file()]
    incomplete = [
        str(r) for r in a.reports if not r.is_file() or '"type":"done"' not in r.read_text(errors="replace")
    ]
    sf, af, files, agg = collect(a.root, reports, read_plans(a.plan))
    a.out.mkdir(parents=True, exist_ok=True)
    (a.out / "standalone-failed.txt").write_text("".join(f + "\n" for f in sorted(sf)))
    (a.out / "agg-failed.txt").write_text("".join(f + "\n" for f in sorted(af)))
    (a.out / "incomplete.txt").write_text("".join(r + "\n" for r in incomplete))
    if a.merge_into:
        merged = json.loads(a.merge_into.read_text()) if a.merge_into.is_file() else {}
        merged.setdefault("files", {}).update({k: round(v * a.scale, 1) for k, v in files.items()})
        merged.setdefault("agg", {}).update({k: round(v * a.scale, 2) for k, v in agg.items()})
        merged["files"] = dict(sorted(merged["files"].items()))
        merged["agg"] = dict(sorted(merged["agg"].items()))
        a.merge_into.write_text(json.dumps(merged, indent=2) + "\n")
    (a.out / "timings.json").write_text(
        json.dumps(
            {
                "files": {k: round(v, 1) for k, v in sorted(files.items())},
                "agg": {k: round(v, 2) for k, v in sorted(agg.items())},
            },
            indent=1,
        )
        + "\n"
    )
    print(
        f"split_collect: {len(sf)} standalone and {len(af)} aggregated failures, "
        f"{len(files)} files and {len(agg)} aggregated files timed"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
