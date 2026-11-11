// Reset Linux forgets the saved "This phone" connection while it is the
// connection in use (the emulator case of N2).
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/builtin/builtin_linux.dart';
import 'package:agentphone/l10n/app_localizations_en.dart';
import 'package:agentphone/platform/platform_capabilities.dart';
import 'package:agentphone/state/connection.dart';
import 'package:agentphone/state/profiles.dart';
import 'package:agentphone/ui/widgets/phone_server_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    debugPlatformCapabilities = const PlatformCapabilities.android();
    for (final name in const [
      'plugins.it_nomads.com/flutter_secure_storage',
      'oc/background',
      'oc/shortcut',
      'oc/termux',
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(name), (call) async => null);
    }
  });
  tearDown(() => debugPlatformCapabilities = null);

  test('the active in-app profile is forgotten and nothing is left', () async {
    SharedPreferences.setMockInitialValues({
      'oc.profiles': jsonEncode([
        {
          'id': 'phone',
          'name': 'This phone',
          'baseUrl': 'http://127.0.0.1:${BuiltinLinux.serverPort}',
          'username': 'opencode',
          'flavor': 'v2',
        },
      ]),
      'oc.activeProfile': 'phone',
    });
    final prefs = await SharedPreferences.getInstance();
    final store = ProfileStore(prefs: prefs);
    await store.load();
    final controller = ConnectionController(store);
    addTearDown(controller.dispose);
    controller.adoptConnectedProfileForTesting(store.profiles.single);

    final problems = await forgetInAppServerProfiles(
      controller,
      AppLocalizationsEn(),
    );

    expect(problems, isEmpty);
    expect(store.profiles, isEmpty);
  });
}
