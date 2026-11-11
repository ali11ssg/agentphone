#!/usr/bin/env bash
# measure.sh DEVICE OUTDIR SCENARIO RUN
#
# One timed repetition of an issue #87 scenario on an emulator, for builds
# with or without OCTRACE. Each run records the screen (adb screenrecord,
# on the device), then tool/qa/issue87/frames.py turns the video into a
# change timeline (10 fps) and prints first_change / settled / settle_time.
# The frames stay in OUTDIR/<scenario>-<run>/ for reading by eye.
#
# Scenarios (labels are the 1.0.44+50 ones; the candidate build may differ,
# where it has OCTRACE use that instead — see the README):
#   cold      force-stop, Home, then `am start -W` (also prints TotalTime =
#             the `Displayed` time). Ends on the Work tab.
#   project   on the Work tab, tap the other-project chip (CHIP=label, or
#             CHIP_XY="x y" when the label is a substring of another, as
#             "proj" of "proj2"). Ends on the Work tab of that project.
#   settings  on the Work tab, tap the Settings tab.
#   gfx-scroll  SurfaceFlinger timestats while flinging a long chat 10 times
#             up and 10 times down (the long chat must be open).
#
# Rules this obeys (AGENTS.md / machine rules): one device, always -s; no
# pattern kills on the PC.
set -euo pipefail
DEV=$1; OUT=$2; SC=$3; RUN=$4
case "$SC" in
  send|gfx-stream)
    echo 'This historical scenario required OpenCode 1 and has been retired.' >&2
    exit 2
    ;;
esac
ADB="${ADB:-$HOME/Android/Sdk/platform-tools/adb} -s $DEV"
PKG=io.github.agentphone.app
HERE=$(cd "$(dirname "$0")" && pwd)
UI="python3 $HERE/../aiteam_builtin/ui.py $DEV"
mkdir -p "$OUT"
D="$OUT/$SC-$RUN"; mkdir -p "$D"

send_xy() { # centre of the Send button, found before the timed part
  $UI find 'Send' | grep -o '\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]' | head -1 |
    tr '[],' '   ' | awk '{print int(($1+$3)/2), int(($2+$4)/2)}'
}

rec() { # seconds, then the action as a command string
  local secs=$1; shift
  $ADB shell rm -f /sdcard/i87.mp4
  $ADB shell screenrecord --time-limit "$secs" /sdcard/i87.mp4 &
  local rp=$!
  sleep 1.5
  date +%s.%N > "$D/action_host_time"
  eval "$@"
  wait $rp || true
  sleep 1
  $ADB pull /sdcard/i87.mp4 "$D/video.mp4" >/dev/null
  python3 "$HERE/frames.py" --length "$secs" "$D/video.mp4" "$D/frames" | tee "$D/summary.txt"
}

case $SC in
  cold)
    $ADB shell am force-stop $PKG
    $ADB shell input keyevent 3
    sleep 3
    rec 16 "$ADB shell am start -W -n $PKG/.MainActivity | tee $D/am_start.txt"
    grep -E 'TotalTime|LaunchState' "$D/am_start.txt"
    ;;
  project)
    if [ -n "${CHIP_XY:-}" ]; then rec 12 "$ADB shell input tap $CHIP_XY"
    else rec 12 "$UI tap \"${CHIP:?set CHIP or CHIP_XY}\""; fi
    ;;
  settings)
    rec 10 "$UI tap 'Settings Tab'"
    ;;
  gfx-scroll)
    $ADB shell dumpsys SurfaceFlinger --timestats -enable -clear >/dev/null
    $ADB shell dumpsys gfxinfo $PKG reset >/dev/null
    for i in 1 2 3 4 5 6 7 8 9 10; do $ADB shell input swipe 540 700 540 1800 120; sleep 0.4; done
    for i in 1 2 3 4 5 6 7 8 9 10; do $ADB shell input swipe 540 1800 540 700 120; sleep 0.4; done
    $ADB shell dumpsys SurfaceFlinger --timestats -dump > "$D/timestats.txt"
    $ADB shell dumpsys gfxinfo $PKG framestats > "$D/gfxinfo.txt"
    $ADB shell dumpsys SurfaceFlinger --timestats -disable >/dev/null
    python3 "$HERE/timestats.py" "$D/timestats.txt" | tee "$D/summary.txt"
    grep -E 'Total frames rendered|Janky frames:' "$D/gfxinfo.txt" | tee -a "$D/summary.txt"
    ;;
  *) echo "unknown scenario $SC" >&2; exit 2 ;;
esac
