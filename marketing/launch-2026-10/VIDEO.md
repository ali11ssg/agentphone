# Demo video storyboard

A 45-second horizontal-safe demo and a 15-second vertical cut, built only from
app states that exist today and that an Android emulator can show. Nothing was
recorded here; this is the shot list for whoever captures it. Every shot names
the screen, the action and the caption.

## What the footage may and may not show

- Real app only. No mock-ups, no goldens. The repo has Flutter golden renders
  (for example `docs/qa/widgets-v2-2026-10-15/*-dark.png`,
  `docs/qa/agent-handoff-ui-2026-10-14/*.png`); do not film or use them as if
  they were device footage.
- Windows with `FLAG_SECURE` record black. The widget style window, the steer
  box and the voice box are secure (see `docs/qa/widgets-v2-2026-10-15/emulator-2320.md`).
  Do not plan shots inside them. The widget on the home screen is not secure
  and records fine (`w-12-permission-widget.png` is a real capture).
- A throwaway model account or key. Never show an API key, a sign-in code or a
  server password on screen; scrub the field before recording. Use OpenCode's
  free model if it works at record time. In the widget proof the free cloud
  models refused with a 403 from a non-OpenCode client, so check that the
  free model works from the app on the day, or use a throwaway key.
- Known rough edges to avoid on camera (from the emulator proof): a
  conversation with no title shows a raw "New session - 2026-10-15T04:39..."
  (finding B5), and "Action sent" lingers in the widget header (B4). Name the
  conversation first and end the shot soon after the tap.
- Widgets show Allow and Reject with the app closed only when "Stay connected
  in the background" is on (finding B3). Turn it on before recording and do not
  claim more than that.
- Claims in captions must be true as stated. "Installs Ubuntu on the phone"
  and "runs Claude Code and OpenCode on the phone" are true per the README.
  Do not caption "faster", "cheaper" or any number.

## Setup for capture (for the operator; not run here)

- Emulator: Pixel_6, Android 14 (the widget proof used it) or the Android 15
  image used for the AI Team proof. x86_64 is supported (the app ships
  x86_64 and arm64-v8a native libraries). Give it enough RAM for the Ubuntu
  setup (the memory note in the README: about 2 GB phones work, slowly).
- Install the 1.4.0 release APK from GitHub releases (not a debug build;
  debug builds do not work with this engine).
- Pre-stage: run the guided setup once off camera so the setup shot can be a
  recorded take of a fresh install on a second AVD with the middle sped up. A
  fresh setup takes about 4 minutes and needs about 210 MB of downloads.
- A small demo project folder, for example a tiny script, so the first
  prompt is quick and cheap. Use a plain prompt such as "Add a --version
  flag to cli.py". Check the exact wording against what the model does.
- Record with `adb shell screenrecord --size 1080x2400 --bit-rate 8000000`
  (the tool stops at 180 s; one take per shot), pull the files, edit
  later. Hide the system navigation hint if it distracts. Turn on "Show
  taps" for the widget shots.
- For the vertical cut, record at 1080x1920 (`adb shell wm size 1080x1920`,
  reset afterwards with `adb shell wm size reset`) so that nothing has to be
  cropped. Check the layout at that aspect ratio before recording.
- Captions are burned-in text, 2 lines at most, same font throughout.
  No music is needed; if music is added it must be licensed for reuse and the
  source must be recorded in the repo. A voice-over is not required.

## 45-second cut (portrait footage)

Output: 1080x1920 portrait video with a plain background pad if a 16:9 export
is needed. Length: 45.0 s. Shot lengths add to 45.

| # | Time | Screen and action | Caption (on screen) | Source |
| --- | --- | --- | --- | --- |
| 1 | 0.0 to 4.0 (4 s) | Welcome screen "choose where your agent runs". Hold; the cursor taps "On this phone". | "Claude Code and OpenCode. On your phone." | fresh install take (like `phoneScreenshots/1_welcome.jpg`) |
| 2 | 4.0 to 11.0 (7 s) | Guided setup on this phone: steps tick through Ubuntu, Git, Node, OpenCode. Sped up 8x; show a "sped up" tag. | "It installs its own Ubuntu inside the app. No computer, no Termux." and, small, "First setup: about 4 min, about 210 MB (sped up)" | setup take (like `phoneScreenshots/2_setup_on_phone.jpg`) |
| 3 | 11.0 to 18.0 (7 s) | New conversation. Type the prompt, tap send. The live line says what the agent is doing; a reply streams; Stop is visible. | "Ask. Watch it work. Stop any time." | chat take (like `phoneScreenshots/3_chat.jpg`) |
| 4 | 18.0 to 25.0 (7 s) | A permission request appears above the message box. Tap "Allow once" (or Allow). The run continues. | "It asks before it edits or runs a command." | approval take (like `phoneScreenshots/4_approve.jpg`) |
| 5 | 25.0 to 31.0 (6 s) | Claude Code conversation: open the Changes tab and show the diff of the edit; scroll once. Use a Claude Code chat so the Files/Changes tabs exist. | "Review the change on the phone." | Claude Code take (like `docs/releases/v1.3.0+53/img/after/03-claude-changes.jpg`) |
| 6 | 31.0 to 40.0 (9 s) | Press Home. The conversations widget shows "1 running, 1 needs you" with Allow once / Reject. Tap Allow once; the widget goes back to running; the app is never opened. | "New in 1.4.0: Allow, Reject, Stop or Steer from the home screen." | widget take (like `docs/qa/widgets-v2-2026-10-15/img/w-12-permission-widget.png` and `w-13-after-allow.png`) |
| 7 | 40.0 to 45.0 (5 s) | End card on a plain dark background. No app footage. | Line 1 "AgentPhone for Android". Line 2 "Free. MIT. Independent." Line 3 "github.com/Eslamasabry/opencode-mobile-next". Small: "Public alpha. Not affiliated with OpenCode or Anthropic." | text only |

Sum check: 4 + 7 + 7 + 7 + 6 + 9 + 5 = 45.

Notes per shot:

- Shot 2 must be a real setup take, accelerated, with the tag. If the
  first-run setup fails on the capture AVD, fix that first; do not substitute.
- Shot 4 depends on the model needing a permission; pick the prompt so that it
  edits a file (an "Asks first" mode run). Check the permission mode before
  recording.
- Shot 5 is Claude Code, which needs a sign-in on the phone. Use a throwaway
  account and sign in off camera. If that is impractical, drop shot 5 and give
  shot 4 or 6 the 6 seconds; do not show OpenCode's Changes view unless it
  exists for OpenCode conversations (the 1.3.0 notes tie Files, Changes and
  Terminal to Claude Code chats).
- Shot 6: Android shows the widget only after it is placed. Place it
  before recording (the style window is secure and records black, so place it
  off camera). Turn on "Stay connected in the background" first.
- Do not show the widget style window, the steer box or the voice box.
- Do not show the live backgrounds in the main cut; they are pretty but add
  nothing to the hook. They could be a 3-second bonus shot of Settings,
  Appearance, Effects only if the take is clean, and it must not push the
  length past 45 s.

## 15-second vertical cut (X, Shorts, Reels)

Output: 1080x1920, 15.0 s, captions inside the safe area (about 150 px from
the top and 250 px from the bottom, to clear platform UI). First frame must
read without sound: a phone screen with the caption already on it.

| # | Time | Screen and action | Caption |
| --- | --- | --- | --- |
| 1 | 0.0 to 3.0 (3 s) | Chat with a streaming reply and the live line; Stop visible. Start on a moving frame. | "Claude Code. On your phone." |
| 2 | 3.0 to 7.0 (4 s) | The permission request above the message box; tap Allow once; run continues. | "No computer. No Termux." |
| 3 | 7.0 to 12.0 (5 s) | Home screen; the widget needs you; tap Allow once; app stays closed. | "Allow from the home screen." |
| 4 | 12.0 to 15.0 (3 s) | End card. | "AgentPhone. Free. MIT. github.com/Eslamasabry/opencode-mobile-next" |

Sum check: 3 + 4 + 5 + 3 = 15. Put "Independent, not affiliated with OpenCode
or Anthropic" in the post text and the profile, since there is little room on
screen.

The vertical cut reuses takes 3, 4 and 6 of the main cut, recorded at
1080x1920 so that no crop is needed.

## Export and use

- Container and codec: H.264 MP4, AAC silent track is fine. X accepts up to
  140 s and 512 MB; Shorts needs under 60 s; keep the main cut under 20 MB so it
  can be linked from the repo README as a file or hosted video. (Platform
  limits are from memory; check each upload form.)
- Add a poster frame: shot 3 or shot 6 (not the end card).
- Subtitle file: provide an `.srt` with the captions above, so the video also
  works in the repo and in Reddit posts with auto captions off.
- Where the video goes: first image or video in every post in POSTS.md; link in
  the README near the top once it is recorded and approved by the owner.
- Record a short evidence note for the audit trail (device or AVD, APK
  version and hash, date, what was sped up) beside the file, following
  `docs/qa/<feature>-<date>/README.md`.

## Stills to pull from the footage (one screen per image)

Following the project rule of one full real screen per image: shot 3 chat,
shot 4 permission, shot 5 Changes, shot 6 widget. These replace the
older `phoneScreenshots/` images in posts once they exist.
