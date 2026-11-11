# BUILD_FOR_MANUS.md — building AgentPhone from source

This file is for whoever (or whatever) builds the APK when GitHub Actions is
not available. Everything below was taken from the real upstream project and
verified against its CI configuration.

## Repository

- Upstream (MIT, kept with its notices): `https://github.com/Eslamasabry/opencode-mobile-next`
- Fork: `https://github.com/<owner>/agentphone`
- Branch built here: `main`
- Version to build: the commit tagged `v*` (release tags are what publish APKs).

## Toolchain (pinned — do not use "latest")

| Tool | Version | Where it comes from |
| --- | --- | --- |
| Flutter | **3.47.2** (stable) | `subosito/flutter-action@v2.23.0` with `flutter-version: 3.47.2` |
| Dart SDK | 3.13.2 | ships with Flutter 3.47.2 |
| JDK | **17** (Temurin) | `actions/setup-java@v6` |
| Gradle | **9.5.0** | `android/gradle/wrapper/gradle-wrapper.properties` (SHA-256 pinned) |
| Android Gradle Plugin | 9.3.2 | `android/settings.gradle.kts` |
| Kotlin | 2.4.0 | `android/settings.gradle.kts` |
| compileSdk | 37 | `android/app/build.gradle.kts` |
| minSdk | 26 | `android/app/build.gradle.kts` |
| targetSdk | pinned number (not `flutter.targetSdkVersion`) | `android/app/build.gradle.kts` |
| ABIs | `arm64-v8a`, `x86_64` | `android/app/src/main/jniLibs/` (PRoot ships as a native library) |

The upstream project releases with Shorebird. This fork does **not**: it builds
with stable Flutter, so `shorebird_code_push` and every Shorebird step are
removed. `tool/verify/verify_all.py` fails the build if a Shorebird leftover
reappears.

## Exact commands

```bash
git clone https://github.com/<owner>/agentphone.git
cd agentphone

# Flutter 3.47.2 must be on PATH (or use the action in CI)
flutter --version          # must print 3.47.2
flutter pub get

dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test --no-pub --concurrency=1

python3 tool/verify/verify_all.py     # permissions, analytics, secrets, licenses
```

### Signing

The keystore is **never** in the repository. It comes from a secret.

```bash
mkdir -p keystore
printf '%s' "$AGENTPHONE_KEYSTORE_B64" | base64 -d > keystore/agentphone-release.p12
chmod 600 keystore/agentphone-release.p12

cat > android/key.properties <<EOF
keyAlias=$AGENTPHONE_KEY_ALIAS
keyPassword=$AGENTPHONE_KEYSTORE_PASSWORD
storeFile=keystore/agentphone-release.p12
storePassword=$AGENTPHONE_KEYSTORE_PASSWORD
storeType=PKCS12
EOF
```

`android/key.properties` and `keystore/` are git-ignored. The key was created
with OpenSSL (the build phone has no JDK, so `keytool` was unavailable):

```bash
openssl req -x509 -newkey rsa:4096 -sha256 -days 9125 -nodes \
  -keyout key.pem -out cert.pem -subj "/C=SA/O=AgentPhone/CN=AgentPhone Release"
openssl pkcs12 -export -out agentphone-release.p12 -inkey key.pem -in cert.pem \
  -name agentphone -passout "pass:$PASSWORD"
```

### Building the APKs

```bash
flutter build apk --release --split-per-abi
# outputs:
#   build/app/outputs/flutter-apk/app-arm64-v8a-release.apk   <- the phone
#   build/app/outputs/flutter-apk/app-x86_64-release.apk
cd build/app/outputs/flutter-apk && sha256sum *.apk > SHA256SUMS
```

The release build is R8-shrunk and not debuggable. `minifyEnabled` and
`shrinkResources` are explicit in `android/app/build.gradle.kts`.

## Native libraries that must be present

PRoot is not downloaded at build time; it ships inside the APK:

```
android/app/src/main/jniLibs/arm64-v8a/libproot.so
android/app/src/main/jniLibs/arm64-v8a/libproot-loader.so
android/app/src/main/jniLibs/arm64-v8a/libaiteam_engine.so
android/app/src/main/jniLibs/arm64-v8a/libaiteam_sandbox.so
```

Modern Android forbids executing binaries from writable app folders, which is
why PRoot runs from the native library directory (`BuiltinLinux.kt`).

The release build also runs `tool/qa/verify_phone_engine_apk.py`, which hashes
the packaged AI Team executables and compares them with
`android/app/src/main/assets/aiteam-engine-manifest.json`. If that check
fails, the APK is not shippable.

## Common errors and fixes

| Symptom | Cause | Fix |
| --- | --- | --- |
| `aapt2` fails on a phone build | aapt2 has no `linux-arm64` build | build on x86_64 (CI or a desktop); never on the phone |
| `Failed to read key.properties` | missing signing file | create `android/key.properties` (above) |
| `keystore password was incorrect` | `storeType` mismatch | the keystore is PKCS#12: set `storeType=PKCS12` |
| `Duplicate class com.google.firebase...` | Firebase plugin still applied | `com.google.gms.google-services` and `com.google.firebase.crashlytics` must not be applied (removed in this fork) |
| Gradle daemon OOM in CI | `org.gradle.jvmargs=-Xmx8G` | set `-Xmx4G` for a 7 GB runner, or use a bigger runner |
| `google-services.json` missing | upstream copies it from `OC_GOOGLE_SERVICES_DIR` | this fork has no Firebase; that copy step was removed |
| Flutter version mismatch | `pubspec.lock` was resolved with another SDK | delete `pubspec.lock` only on purpose; `flutter pub get` with 3.47.2 otherwise |

## What the fork changed

1. Application id `io.github.agentphone.app` (the upstream app keeps
   `io.github.eslamasabry.opencode_mobile`, so both can be installed side by
   side).
2. Firebase removed completely (Dart packages, Gradle plugins, manifest
   metadata, telemetry module). No analytics, no crash reporting.
3. Android permissions reduced to: `INTERNET`, `POST_NOTIFICATIONS`,
   `FOREGROUND_SERVICE` (+ `specialUse` / `dataSync` types), `WAKE_LOCK`,
   `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, `USE_BIOMETRIC`.
   Features that needed more (camera QR pairing, voice input, shared-storage
   projects, scheduled prompts, in-app APK update) are disabled in the UI.
4. Flutter stable instead of Shorebird.
5. New launcher icon and app name (`AgentPhone`), plus a "not affiliated"
   note in About.
