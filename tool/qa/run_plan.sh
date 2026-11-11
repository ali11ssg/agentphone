#!/usr/bin/env bash
# Run one machine's half of a split plan (written by tool/qa/split_plan.py).
#
#   tool/qa/run_plan.sh JOBS REPORT.json < half.plan
#
# stdin lines: "F <file>" runs the file alone; "A <bundle> <file>" puts the file
# in build/agg/shard_<bundle>_test.dart, which tool/qa/gen_aggregates.py
# generates here (one process for many small files). Prints failing tests only;
# REPORT.json gets the JSON event stream for tool/qa/split_collect.py.
# Exit code is flutter test's.
set -uo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
jobs="$1"
report="$2"
plan="$(mktemp)"
trap 'rm -f "$plan"' EXIT
cat >"$plan"
rm -rf build/agg
targets=()
while read -r kind rest; do
  [[ "$kind" == F ]] && targets+=("$rest")
done <"$plan"
if grep -q '^A ' "$plan"; then
  while read -r path; do targets+=("$path"); done < <(
    sed -n 's/^A //p' "$plan" | python3 tool/qa/gen_aggregates.py write --out build/agg |
      sed 's|^.*/build/agg/|build/agg/|')
fi
mkdir -p "$(dirname "$report")"
exec flutter test -j "$jobs" --reporter=failures-only --file-reporter "json:$report" "${targets[@]}"
