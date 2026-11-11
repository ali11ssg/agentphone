#!/usr/bin/env python3
"""Plan a full test run across this machine ("local") and the build server ("remote").

    split_plan.py --all all.txt --out DIR [--local-slots 3] [--remote-slots 6]
                  [--remote-speed 0.33] [--aggregate eligible.txt --bundles 8]

``all.txt`` lists every test file (one per line). Each file weighs its measured
seconds from tool/qa/test_timings.json (files with no weight get the median).
Both machines run goldens (exact comparison, plus the small per-image list in
test/goldens/tolerances.json), so a file may go to either side. Every slot of
every machine is simulated: files are handed out longest first to the slot that
would finish them earliest, a remote slot being ``remote-speed`` times as fast
as a local one. The result is written to DIR/local.txt and DIR/remote.txt.

With ``--aggregate``, the listed small files are not placed one by one: they are
packed into ``--bundles`` aggregated entrypoints (tool/qa/gen_aggregates.py) of
about equal weight, and each bundle is placed like one file. The plan files
DIR/local.plan and DIR/remote.plan hold "F <file>" for a standalone file and
"A <bundle> <file>" for a bundle member; local.txt/remote.txt list every file.
"""

from __future__ import annotations

import argparse
import heapq
import json
import statistics
from pathlib import Path


def load_weights(path: Path) -> dict[str, float]:
    if not path.is_file():
        return {}
    data = json.loads(path.read_text())
    return {k: float(v) for k, v in data.get("files", {}).items()}


# Seconds of load and compile one aggregated entrypoint costs on top of its tests.
BUNDLE_OVERHEAD = 15.0
# A file measured above this many seconds runs alone, never inside a bundle.
MAX_BUNDLED_SECONDS = 20.0
# Standalone seconds of a file that are process start and load, not tests.
LOAD_SECONDS = 4.4


def load_agg_weights(path: Path) -> dict[str, float]:
    if not path.is_file():
        return {}
    data = json.loads(path.read_text())
    return {k: float(v) for k, v in data.get("agg", {}).items()}


def make_bundles(
    members: list[str],
    weights: dict[str, float],
    agg_weights: dict[str, float],
    count: int,
) -> tuple[dict[int, list[str]], dict[int, float]]:
    """Pack files into ``count`` bundles of about equal weight (longest first)."""
    solo = {f: weights.get(f) for f in members}
    known = [v for v in solo.values() if v is not None]
    fallback = statistics.median(known) if known else 1.0

    def in_bundle(f: str) -> float:
        if f in agg_weights:
            return agg_weights[f] + 0.2
        return max(0.3, (solo[f] if solo[f] is not None else fallback) - LOAD_SECONDS)

    bundles: dict[int, list[str]] = {i: [] for i in range(count)}
    load = [0.0] * count
    for f in sorted(members, key=lambda f: (-in_bundle(f), f)):
        i = min(range(count), key=lambda j: (load[j], j))
        bundles[i].append(f)
        load[i] += in_bundle(f)
    bundles = {i: sorted(m) for i, m in bundles.items() if m}
    seconds = {i: BUNDLE_OVERHEAD + sum(in_bundle(f) for f in m) for i, m in bundles.items()}
    return bundles, seconds


def plan(
    files: list[str],
    weights: dict[str, float],
    local_slots: int,
    remote_slots: int,
    remote_speed: float,
    bundles: dict[int, list[str]] | None = None,
    bundle_weight: dict[int, float] | None = None,
) -> tuple[list[str], list[str], float, float]:
    """Return (local files, remote files, local seconds, remote seconds).

    With ``bundles`` the bundled files are placed as units; ``plan.last_units``
    records which unit each machine got ("F", file) or ("A", bundle).
    """
    bundles = bundles or {}
    bundled = {f for m in bundles.values() for f in m}
    solo_files = [f for f in files if f not in bundled]
    known = [weights[f] for f in solo_files if f in weights]
    fallback = statistics.median(known) if known else 1.0
    weight = {("F", f): weights.get(f, fallback) for f in solo_files}
    for i in bundles:
        weight[("A", i)] = (bundle_weight or {}).get(i, BUNDLE_OVERHEAD + len(bundles[i]))
    # (finish time, slot index, speed, machine)
    heap = [(0.0, i, 1.0, "local") for i in range(local_slots)]
    heap += [(0.0, local_slots + i, remote_speed, "remote") for i in range(remote_slots)]
    heapq.heapify(heap)
    units: dict[str, list[tuple[str, object]]] = {"local": [], "remote": []}
    for u in sorted(weight, key=lambda u: (-weight[u], str(u[1]))):
        # Place on the slot that would finish this unit earliest.
        best = min(heap, key=lambda s: (s[0] + weight[u] / s[2], s[1]))
        heap.remove(best)
        finish, idx, speed, machine = best
        units[machine].append(u)
        heap.append((finish + weight[u] / speed, idx, speed, machine))
    span = {m: max([s[0] for s in heap if s[3] == m] or [0.0]) for m in units}
    plan.last_units = units  # type: ignore[attr-defined]
    picked = {
        m: sorted(
            u[1] if u[0] == "F" else f
            for u in us
            for f in ([u[1]] if u[0] == "F" else bundles[u[1]])  # type: ignore[index]
        )
        for m, us in units.items()
    }
    return picked["local"], picked["remote"], span["local"], span["remote"]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--all", required=True, type=Path)
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--timings", type=Path, default=Path("tool/qa/test_timings.json"))
    ap.add_argument("--local-slots", type=int, default=3)
    ap.add_argument("--remote-slots", type=int, default=6)
    ap.add_argument("--remote-speed", type=float, default=0.33)
    ap.add_argument("--aggregate", type=Path, help="files that may be aggregated")
    ap.add_argument("--bundles", type=int, default=8)
    a = ap.parse_args()
    files = [l.strip() for l in a.all.read_text().splitlines() if l.strip()]
    weights = load_weights(a.timings)
    bundles: dict[int, list[str]] = {}
    bundle_weight: dict[int, float] = {}
    if a.aggregate:
        pool = [l.strip() for l in a.aggregate.read_text().splitlines() if l.strip()]
        pool = [f for f in pool if f in set(files) and weights.get(f, 0) <= MAX_BUNDLED_SECONDS]
        bundles, bundle_weight = make_bundles(
            pool, weights, load_agg_weights(a.timings), a.bundles
        )
    local, remote, ls, rs = plan(
        files, weights, a.local_slots, a.remote_slots, a.remote_speed, bundles, bundle_weight
    )
    a.out.mkdir(parents=True, exist_ok=True)
    (a.out / "local.txt").write_text("".join(f + "\n" for f in local))
    (a.out / "remote.txt").write_text("".join(f + "\n" for f in remote))
    for machine in ("local", "remote"):
        lines = []
        for kind, ref in plan.last_units[machine]:  # type: ignore[attr-defined]
            if kind == "F":
                lines.append(f"F {ref}")
            else:
                lines += [f"A {ref} {f}" for f in bundles[ref]]  # type: ignore[index]
        (a.out / f"{machine}.plan").write_text("".join(l + "\n" for l in sorted(lines)))
    print(f"split_plan: {len(local)} local (~{ls:.0f}s), {len(remote)} remote (~{rs:.0f}s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
