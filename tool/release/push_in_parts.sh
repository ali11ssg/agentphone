#!/usr/bin/env bash
# Pushes the fork to GitHub in pieces.
#
# The whole tree is about 190 MB (4,873 golden images), and one 190 MB push
# times out on this link with an HTTP 408 from GitHub. The history is
# therefore rewritten as a fresh branch that adds the images in chunks: each
# push stays small enough for the link, and `main` ends up at the last commit.
#
# The working tree is never touched: only the index and the branch.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."
BRANCH="${AGENTPHONE_PUSH_BRANCH:-fork-main}"
CHUNKS="${AGENTPHONE_PUSH_CHUNKS:-5}"

echo "== preparing a fresh history on $BRANCH"
git checkout --orphan "$BRANCH"
git rm -rq --cached . > /dev/null 2>&1 || true
git add -A -- . ':(exclude)test/**/*.png'
git commit -q -m "Import upstream MIT project opencode-mobile-next v2.1.5+63

AgentPhone starts from the MIT-licensed Flutter + Kotlin project
Eslamasabry/opencode-mobile-next (Copyright (c) its authors, MIT).
The LICENSE, NOTICE and THIRD_PARTY_NOTICES.md files are kept unchanged;
this fork adds its own changes under the same license.

Co-Authored-By: AgentPhone Builder <agentphone@local>"
git push -u origin "$BRANCH"

echo "== adding the golden images in $CHUNKS parts"
mapfile -t images < <(git ls-files --others --exclude-standard -- 'test/**/*.png')
total=${#images[@]}
if [ "$total" -eq 0 ]; then
  echo "no images to add"
else
  size=$(( (total + CHUNKS - 1) / CHUNKS ))
  for ((part = 0; part < CHUNKS; part++)); do
    start=$((part * size))
    if [ "$start" -ge "$total" ]; then break; fi
    end=$((start + size))
    if [ "$end" -gt "$total" ]; then end=$total; fi
    chunk=("${images[@]:start:size}")
    git add -- "${chunk[@]}"
    git commit -q -m "Add the golden images (part $((part + 1)) of $CHUNKS)

Co-Authored-By: AgentPhone Builder <agentphone@local>"
    git push origin "$BRANCH"
    echo "   part $((part + 1)): $((end - start)) files"
  done
fi

echo "== main now points at $BRANCH"
git branch -f main "$BRANCH"
git checkout -q main
git push -u origin main
echo "== done"
git log --oneline -3
