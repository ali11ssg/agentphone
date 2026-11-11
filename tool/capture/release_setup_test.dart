// Synthetic screenshots of the actual release setup widgets, with no device data.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/builtin/setup/setup_contract.dart';
import 'package:agentphone/l10n/app_localizations.dart';
import 'package:agentphone/ui/screens/phone_setup/phone_setup_progress_screen.dart';

import '../../test/revamp/screen_phone_1_fixtures.dart';
import '../../test/support/fake_setup_engine.dart';
import 'fixtures.dart' show loadCaptureFonts, capturePng, writePng;

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  setUpAll(loadCaptureFonts);
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (_) async => null,
        );
  });
  const output = 'docs/qa/release-device-pass-2026-10-15';
  testWidgets('Python repair words and Details', (tester) async {
    final l10n = lookupAppLocalizations(const Locale('en'));
    final engine = FakeSetupEngine()
      ..emit(
        SetupProgress(
          state: SetupState.failed,
          current: 'python',
          overall: .5,
          error: l10n.phoneSetupErrorPackageRepair,
          logTail:
              'dpkg --audit\nlibonig5:amd64: install reinstreq half-installed',
          components: [
            const ComponentProgress(
              id: 'linux',
              state: ComponentState.done,
              version: '24.04.5',
            ),
            const ComponentProgress(
              id: 'essentials',
              state: ComponentState.done,
              version: '2.43.0',
            ),
            ComponentProgress(
              id: 'python',
              state: ComponentState.failed,
              error: l10n.phoneSetupErrorPackageRepair,
            ),
          ],
        ),
      );
    final boundary = GlobalKey();
    await pumpPhone(
      tester,
      boundary: boundary,
      home: PhoneSetupProgressScreen(engine: engine),
    );
    await _frames(tester);
    await tester.ensureVisible(find.text('Details'));
    await _frames(tester);
    await writePng(
      '$output/setup-python-repair.png',
      await capturePng(tester, boundary, pixelRatio: 2),
    );
    await tester.tap(find.text('Details'));
    await _frames(tester);
    await writePng(
      '$output/setup-python-details.png',
      await capturePng(tester, boundary, pixelRatio: 2),
    );
    expect(tester.takeException(), isNull);
    await unmountPhone(tester);
  });
}
