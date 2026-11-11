// The fork's release contract.
//
// AgentPhone is built by GitHub Actions on an x86_64 runner (the phone cannot
// build an APK: Android's aapt2 has no ARM64 Linux build). This test keeps
// the pieces of that contract true: the pinned toolchain, the signing path,
// the checksums, the identity, and the fact that the key never enters the
// repository.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final workflow = File(
    '.github/workflows/agentphone-android.yml',
  ).readAsStringSync();

  group('the build workflow', () {
    test('pins the toolchain', () {
      expect(workflow, contains('FLUTTER_VERSION: "3.47.2"'));
      expect(workflow, contains('JAVA_VERSION: "17"'));
      expect(workflow, isNot(contains('latest')));
    });

    test('runs the gates before the build', () {
      expect(workflow, contains('flutter analyze'));
      expect(workflow, contains('flutter test'));
      expect(
        workflow,
        contains('dart format --output=none --set-exit-if-changed'),
      );
      expect(workflow, contains('tool/verify/verify_all.py'));
    });

    test('signs from a secret, never from the tree', () {
      expect(workflow, contains('secrets.AGENTPHONE_KEYSTORE_B64'));
      expect(workflow, contains('secrets.AGENTPHONE_KEYSTORE_PASSWORD'));
      expect(workflow, contains('android/key.properties'));
      // The key itself is never written into the repository.
      expect(workflow, isNot(contains('BEGIN PRIVATE KEY')));
    });

    test('publishes the APK with its checksums', () {
      expect(workflow, contains('--split-per-abi'));
      expect(workflow, contains('sha256sum'));
      expect(workflow, contains('SHA256SUMS'));
      expect(workflow, contains('gh release create'));
    });
  });

  group('the identity', () {
    test('the application id is the fork\'s, not the upstream\'s', () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle, contains('applicationId = "io.github.agentphone.app"'));
      expect(
        gradle,
        isNot(
          contains('applicationId = "io.github.eslamasabry.opencode_mobile"'),
        ),
      );
      expect(gradle, contains('namespace = "io.github.agentphone.app"'));
    });

    test('the app label and the Dart package name are the fork\'s', () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle, contains('"AgentPhone"'));
      expect(
        File('pubspec.yaml').readAsStringSync(),
        contains('name: agentphone'),
      );
    });

    test('the launcher icon exists for every density', () {
      for (final density in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
        final icon = File(
          'android/app/src/main/res/mipmap-$density/ic_launcher.png',
        );
        expect(icon.existsSync(), isTrue, reason: density);
        expect(icon.lengthSync(), greaterThan(0));
      }
    });

    test('the about screen states that the project is independent', () {
      final about = File('lib/ui/screens/about_screen.dart').readAsStringSync();
      expect(about, contains('independent community project'));
      expect(about, contains('not affiliated'));
    });
  });

  group('the signing key', () {
    test('the key example names the keystore and its type', () {
      final example = File('android/key.properties.example').readAsStringSync();
      expect(example, contains('storeFile='));
      expect(example, contains('keyAlias='));
      expect(example, contains('storePassword='));
    });

    test('the key and the properties never enter the repository', () {
      final ignored = File('.gitignore').readAsStringSync();
      expect(ignored, contains('keystore/'));
      expect(ignored, contains('android/key.properties'));
      for (final path in ['keystore', 'android/key.properties']) {
        expect(
          Directory(path).existsSync() || File(path).existsSync(),
          isFalse,
          reason: '$path must not exist in the tree',
        );
      }
    });
  });
}
