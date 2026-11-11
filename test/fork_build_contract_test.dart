// The fork's own build contract.
//
// The upstream project shipped several build variants (a code-push build, an
// F-Droid build that removes the proprietary packages). AgentPhone ships one
// build: no code-push service, no vendor SDK, no camera and no microphone.
// These tests keep that true.
//
// The permission gate lives in tool/verify/verify_permissions.py and runs in
// CI; the copy in this file is the same list, so a change in one place that
// forgets the other is caught by the other.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/platform/platform_capabilities.dart';
import 'package:agentphone/update/shorebird_updater_stub.dart' as updater_stub;
import 'package:agentphone/update/app_update_service.dart';

void main() {
  group('capabilities', () {
    test('no feature that needs a missing permission is offered', () {
      const caps = PlatformCapabilities(platform: TargetPlatform.android);
      // No microphone permission, no camera permission, no patch service.
      expect(caps.supportsVoice, isFalse);
      expect(caps.supportsQrPairing, isFalse);
      expect(caps.supportsCodePush, isFalse);
      // The rest of the phone is still there.
      expect(caps.isAndroid, isTrue);
      expect(caps.supportsBackgroundService, isTrue);
      expect(caps.supportsThisPhone, isTrue);
      expect(caps.supportsNotifications, isTrue);
    });

    test('the F-Droid answer is the shipping answer: there is one build', () {
      expect(
        const PlatformCapabilities(
          platform: TargetPlatform.android,
          fdroid: true,
        ),
        const PlatformCapabilities(platform: TargetPlatform.android),
      );
    });
  });

  group('stand-ins', () {
    test('the updater stand-in can never find or fetch an update', () async {
      final service = updater_stub.ShorebirdAppUpdateService();
      expect(service.isAvailable, isFalse);
      expect(await service.checkForUpdate(), AppUpdateState.unavailable);
      await service.downloadUpdate();
    });
  });

  group('where a vendor package may be named', () {
    test('no Dart file imports a code-push or vendor package', () {
      final importers = <String, List<String>>{
        'shorebird_code_push': [],
        'mobile_scanner': [],
        'google_mlkit_barcode_scanning': [],
        'firebase_core': [],
        'firebase_analytics': [],
        'firebase_crashlytics': [],
        'firebase_performance': [],
        'camera': [],
        'record': [],
      };
      for (final file in Directory('lib').listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        final text = file.readAsStringSync();
        for (final name in importers.keys) {
          if (text.contains("import 'package:$name/")) {
            importers[name]!.add(file.path);
          }
        }
      }
      for (final entry in importers.entries) {
        expect(entry.value, isEmpty, reason: entry.key);
      }
    });

    test('the updater export is the stand-in, not the real service', () {
      expect(
        File('lib/update/shorebird_update_notice.dart').readAsStringSync(),
        contains("export 'shorebird_updater_stub.dart';"),
      );
      expect(
        File('lib/update/shorebird_updater_real.dart').existsSync(),
        isFalse,
      );
    });
  });

  group('permissions', () {
    test('the manifest asks for nothing outside the allowed list', () {
      const allowed = {
        'android.permission.INTERNET',
        'android.permission.POST_NOTIFICATIONS',
        'android.permission.FOREGROUND_SERVICE',
        'android.permission.FOREGROUND_SERVICE_SPECIAL_USE',
        'android.permission.FOREGROUND_SERVICE_DATA_SYNC',
        'android.permission.WAKE_LOCK',
        'android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
        'android.permission.USE_BIOMETRIC',
      };
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      final declared = RegExp(
        r'<uses-permission[^>]*android:name="([^"]+)"',
      ).allMatches(manifest).map((m) => m.group(1)!).toSet();
      expect(declared.difference(allowed), isEmpty);
      expect(allowed.difference(declared), isEmpty);
    });
  });
}
