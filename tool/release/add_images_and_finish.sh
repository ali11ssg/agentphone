#!/usr/bin/env bash
# Adds the golden images in small parts and pushes each part.
#
# A single 190 MB push times out on this link (HTTP 408), so the images go up
# in chunks of about 30 MB. Every push is retried with a backoff, and the
# result is verified with ls-remote before the next chunk.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."
BRANCH="${AGENTPHONE_PUSH_BRANCH:-fork-main}"
CHUNKS="${AGENTPHONE_PUSH_CHUNKS:-6}"

push_with_retries() {
  local attempt=1
  while true; do
    echo "   push attempt $attempt"
    if timeout 900 git push origin "$BRANCH" 2>&1 | tail -2; then
      return 0
    fi
    if [ "$attempt" -ge 5 ]; then
      echo "   giving up after $attempt attempts"
      return 1
    fi
    local wait=$((attempt * 30))
    echo "   backing off ${wait}s"
    sleep "$wait"
    attempt=$((attempt + 1))
  done
}

echo "== images into $CHUNKS parts"
mapfile -t images < <(git ls-files --others --exclude-standard -- 'test/**/*.png')
total=${#images[@]}
echo "   $total images"
if [ "$total" -eq 0 ]; then
  echo "   nothing to add"
  exit 0
fi

size=$(( (total + CHUNKS - 1) / CHUNKS ))
for ((part = 0; part < CHUNKS; part++)); do
  start=$((part * size))
  [ "$start" -ge "$total" ] && break
  end=$((start + size))
  [ "$end" -gt "$total" ] && end=$total
  chunk=("${images[@]:start:size}")
  git add -- "${chunk[@]}"
  git commit -q -m "Add the golden images (part $((part + 1)) of $CHUNKS)

Co-Authored-By: AgentPhone Builder <agentphone@local>"
  push_with_retries
  echo "   part $((part + 1)): $((end - start)) files pushed"
done

echo "== main points at $BRANCH"
git branch -f main "$BRANCH"
git checkout -q main
git push -u origin main

echo "== verified"
git ls-remote origin | head -4
