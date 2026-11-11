# Draft release note: the next release

Draft for the owner. No version number or date yet. It covers everything on
branch `int/ui-batch-2026-10-14` since v1.4.0+54, in the two layers of
`docs/releases/v1.4.0+54.md`. Nothing here is released, tagged or proven on a
phone. Lines marked [needs proof: <matrix row>] point at
`docs/qa/real-life-matrix-2026-10-16/README.md`; keep a line only when its row
is PASS for the release build, otherwise delete it. When copying to
`docs/releases/v<version>.md`, remove this paragraph and every marker.

---

# AgentPhone <version>

Run Claude Code and OpenCode from your phone with more control: schedule prompts, preview your dev server, and act from the home screen, in a download a third the size.

## What changed for you

- **Scheduled prompts**: run a prompt at a time you choose, once or repeating, see each run's history, and get a morning summary of what ran. [needs proof: Q1, Q2, Q8]
- **Preview your app**: tap a localhost link in a reply and your running dev server opens inside the app. [needs proof: Q9]
- **Widgets that settle**: after Allow, Reject or Stop, the widget stops saying "working" and shows the agent's latest reply. [needs proof: I5, I6, I7]
- **A much smaller download**: one APK per processor type, about 36 MB for most phones (it was 105 MB). [needs proof: SIZE]
- **Connect to more servers**: after an explicit yes you can use a plain-HTTP server, and you can pin a self-signed certificate. A changed certificate is blocked. [needs proof: B3, B4, B5]
- **Fewer lost messages**: if the app cannot tell whether a message arrived, it keeps it for you to review and never sends it twice. [needs proof: M2, M3]
- **Claude Code on the phone updates and recovers**: the phone check can update Claude Code, show download progress, and go back to the last working version. [needs proof: G1, Q13]
- **OpenCode 2 only**: support for OpenCode 1 has ended. A phone that ran OpenCode 1 moves to OpenCode 2 and keeps its conversations. A remote OpenCode 1 server shows how to upgrade. [needs proof: Q12]

## Technical changes

### Added
- Scheduled prompts:
  - Durable schedules, one-time or repeating, each named by its prompt, with times in your locale format and pause, edit and delete.
  - Run history per schedule, and an optional morning summary that comes before platform notices.
  - Runs with the app closed use bounded Android leases (WorkManager plus alarms) and a bounded start of the phone's own server. A prompt aimed at a temporary phone-agent helper is rejected when no safe lease exists. Interactive sends are guarded while a scheduled phone run is in progress.
  - Profile deletion removes the schedule keys, read late so a schedule cannot be recreated during deletion.
  - A finished one-time schedule reads "no more runs", not "paused". Battery guidance explains exact-alarm and background limits.
- Dev-server preview:
  - A link to `localhost`, `127.0.0.1`, `0.0.0.0` or `::1` with a port opens an in-app Preview of the phone's own server. For another server the link is pointed at that server's host, with a note that the dev server must listen on `0.0.0.0`.
  - The Preview has reload, open in browser, copy address and back. It loads one origin only; any other address leaves through the external-link guard. No JavaScript channel exists, and cookies and storage are cleared on open and close.
  - The conversation menu gains **Preview a running app**, listing the ports the conversation named.
- Plain-HTTP consent and self-signed certificate pinning:
  - A remote `http://` server needs an explicit yes, recorded per profile.
  - A self-signed HTTPS server shows its certificate fingerprint; you pin it. A rotated certificate is rejected until you review it.
- Claude Code phone check: checks and activates the pinned Claude Code and Paseo pair together, classifies helper mismatch, timeout and missing sign-in, shows resumable download progress, explains changed qualification requirements, and offers a verified rollback to the retained version without resetting accounts or chats.
- Release packaging: the release workflow derives `arm64-v8a` and `armeabi-v7a` APKs from the universal one (same files, same signer, so Shorebird patches apply). The arm64 download goes from 105 MB to about 36 MB. Release builds pass `--split-debug-info`, which cuts `libapp.so` by 2 MiB per ABI. Measurements are in `docs/design/apk-size-2026-10-16.md`.

### Changed
- OpenCode 1 is removed. OpenCode 2, direct Codex and Paseo remain. Managed OpenCode 1 installations move to OpenCode 2 with a history import; if the move cannot finish safely the original data stays on disk and the app explains how to retry. Legacy health responses are rejected at connect. The retired runtime switch and host helper guidance are gone, and the original Termux profile is kept after the move.
- Widgets: the idle card shows the model, last activity and **Open**; previews are plain text; the Usage widget is centred and defaults to measured limits; empty launcher cards fill and row density follows launcher size and large text; one connection hint instead of several.
- Schedule screens use plain wording ("summary" throughout), long names are cut in delete questions, confirm buttons name the act, and agent names no longer force upper case.
- A tablet keeps terminal input available with a mouse attached.

### Fixed
- Widget actions reconcile with the server afterwards and keep on-demand state; longer turns settle with the app closed through bounded read-only follow-up checks, and OpenCode 2 idle notices are told apart from user prompts.
- A send is saved before the composer clears. An unknown delivery waits for explicit review, repeated sends are guarded, newer composer edits are kept, and queue diagnostics are redacted.
- Setup and provider failures are explained in plain words; technical detail stays under Details.
- The installed-tools list refreshes after setup instead of reporting a tool as absent.
- An interrupted OpenCode 2 move keeps the selected phone identity and withholds setup capabilities until history is confirmed.
- A conflicting legacy global package is replaced during upgrade.
- AI Team's stop step no longer counts the time spent waiting for your yes.
- Release shrinking keeps the WorkManager constructors that scheduled prompts load by reflection.

### For maintainers
- The suite no longer depends on OpenCode 1 fixtures; the live OpenCode 1 fixture is retired.
- QA split runs use their own server worktree; unsigned builds keep an isolated Gradle cache and use the remote Flutter environment.
- `webview_flutter` is a native addition, so this needs a new release, not a Shorebird patch. Scheduled prompts also change native code. Releases from build 55 apply `--split-debug-info` to patches as well.
