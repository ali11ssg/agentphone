# AgentPhone

A coding agent on your phone. AgentPhone installs its own Linux on the device,
runs an agent engine inside it, and shows you everything the agent does.

- **Your own agent engine on the phone.** The app installs a Linux environment
  (Ubuntu with Git and Node) in its own storage and runs an OpenCode v2 server
  inside it, bound to `127.0.0.1` with a random password.
- **A bottom "Computer panel".** Terminal commands with their full command
  line, working directory, timings, exit code and live output; the files being
  edited and their diffs; the plan; and a browser the agent can drive.
- **Approvals in your hand.** Every command and every edit can ask first, and
  the answer can come from a notification (behind the device lock).
- **An AI team.** A planner, a few executors and an optional reviewer, each
  with its own git worktree, running side by side with a shared cost limit.
- **Nothing leaves the phone unless you send it.** No analytics, no crash
  reporting, no telemetry: see [PRIVACY.md](PRIVACY.md).

## What it is not

AgentPhone is an **independent community project**. It is not built,
maintained, endorsed by, or affiliated with the official OpenCode team, and it
is not affiliated with Anthropic. It uses OpenCode v2 as its agent engine and
talks to it over its documented HTTP API.

## Where it comes from

AgentPhone is a fork of the MIT-licensed project
[`Eslamasabry/opencode-mobile-next`](https://github.com/Eslamasabry/opencode-mobile-next),
which installed a Linux on the phone and ran coding agents inside it. This fork
keeps that work and changes:

| Area | Upstream | AgentPhone |
| --- | --- | --- |
| Application id | `io.github.eslamasabry.opencode_mobile` | `io.github.agentphone.app` (both apps can be installed side by side) |
| Name and icon | OpenCode Mobile | AgentPhone, with a new launcher icon |
| Analytics | Firebase Analytics, Crashlytics and Performance, opt-in | Removed completely: no vendor SDK, no telemetry |
| Code push | Shorebird | Stable Flutter, updates arrive as signed APKs from the release page |
| Permissions | 12 Android permissions | 8: internet, notifications, foreground service, wake lock, battery exemption, biometrics |
| Camera QR scanning, voice recording, shared-storage projects, exact alarms, in-app APK install, boot receivers | enabled | switched off, and the permission is not requested |
| Builds | Shorebird release pipeline | GitHub Actions, pinned Flutter 3.47.2 and JDK 17 |

The original `LICENSE`, `NOTICE` and `THIRD_PARTY_NOTICES.md` are kept; PRoot
is GPL and its notices and source offer are in
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

## Building

The phone cannot build APKs (Android's `aapt2` has no ARM64 Linux build), so
the build runs on a cloud runner. Everything is pinned:

- Flutter **3.47.2** (stable) with Dart **3.13.2**
- JDK **17**, Gradle **9.5.0**, Android Gradle Plugin **9.3.2**, Kotlin **2.4.0**
- compileSdk 37, minSdk 26, targetSdk 36, ABIs `arm64-v8a` and `x86_64`

```bash
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test --no-pub --concurrency=1
python3 tool/verify/verify_all.py     # permissions, analytics, secrets, licences
flutter build apk --release --split-per-abi
```

Signing, the secret names, common build errors and the release steps are in
[`BUILD_FOR_MANUS.md`](BUILD_FOR_MANUS.md).

The release key is created once and lives outside the repository (see
`tool/keystore/make_keystore.sh`). It is uploaded to the repository secrets.
**Keep a copy outside the phone**: Android only accepts an update signed by
the same key, and the Linux environments live inside the app, so uninstalling
is not a way out.

## Repository layout

| Path | What lives there |
| --- | --- |
| `lib/` | Dart code: screens, state (Riverpod), domain logic, the Linux bridge |
| `android/app/src/main/kotlin/` | Kotlin: foreground services, notifications, PRoot |
| `android/app/src/main/jniLibs/` | PRoot and the phone engine, as native libraries |
| `third_party/xterm/` | The terminal widget (MIT), vendored |
| `tool/verify/` | The gates that run before every push |
| `tool/branding/` | The launcher icon and the copy fixes |
| `tool/keystore/` | Creates the release signing key |
| `engine/phone/` | The phone engine (Rust) that runs the AI team |

## Licence

MIT, like the project it comes from. See [`LICENSE`](LICENSE) and
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
