import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/background/live_background.dart';
import 'package:agentphone/builtin/local_terminal.dart';
import 'package:agentphone/platform/platform_capabilities.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_local_terminal.dart';

// The sign-in terminal on the real background controller: what the person
// reads under Details names why Android refused or stopped the service.

const _words = 'Could not keep sign-in running. Try again.';

Map<String, dynamic> _pause({
  bool active = false,
  bool paused = false,
  String reason = 'none',
}) => {
  'supported': true,
  'active': active,
  'paused': paused,
  'reason': reason,
  'at': paused ? 1791417600000 : null,
  'canResume': paused,
};

class _Android {
  _Android(SharedPreferences preferences) {
    controller = BackgroundLiveController(
      preferences: preferences,
      invoke: (method, [arguments]) async {
        calls.add(method);
        switch (method) {
          case 'getBackgroundPause':
            return pause;
          case 'enable':
            running = startFailure == null;
            return status;
          case 'disable':
            running = false;
            return status;
          case 'getStatus':
            return status;
        }
        return const {};
      },
    );
  }

  late final BackgroundLiveController controller;
  final calls = <String>[];
  Map<String, dynamic> pause = _pause();
  String? startFailure;
  bool running = false;

  Map<String, dynamic> get status => {
    'enabled': running,
    'active': running,
    'notificationGranted': true,
    'batteryOptimizationIgnored': false,
    'backgroundPause': _pause(active: running),
    'startFailure': ?startFailure,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Android android;
  late FakeLocalTerminalBackend backend;
  late LocalTerminalSessions sessions;

  setUp(() async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    final oldCapabilities = debugPlatformCapabilities;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    debugPlatformCapabilities = const PlatformCapabilities.android();
    SharedPreferences.setMockInitialValues({});
    android = _Android(await SharedPreferences.getInstance());
    backend = FakeLocalTerminalBackend();
    sessions = LocalTerminalSessions(
      backend: backend,
      signInForeground: android.controller,
    );
    addTearDown(() async {
      sessions.dispose();
      android.controller.dispose();
      await backend.close();
      debugDefaultTargetPlatformOverride = oldPlatform;
      debugPlatformCapabilities = oldCapabilities;
    });
  });

  bool terminalStarted() => backend.calls.any((c) => c.startsWith('sign-in '));

  test('a service Android did not start is named, not called lost', () async {
    for (final (failure, code) in [
      ('ackTimeout', 'service-not-started'),
      ('refused', 'service-refused'),
      ('receiptUnsaved', 'service-receipt-unsaved'),
    ]) {
      android.startFailure = failure;
      final shell = sessions.startSignIn('owner', ['claude', 'auth', 'login']);
      await pumpEventQueue();
      expect(shell.state, LocalShellState.failed);
      expect(shell.failure, '$_words\nCode: sign-in-admission/$code');
      expect(terminalStarted(), isFalse);
    }
  });

  test(
    'a durable pause does not stop a sign-in the person asked for',
    () async {
      for (final reason in ['appUpdated', 'userStopped', 'timeLimit']) {
        android.pause = _pause(paused: true, reason: reason);
        final shell = sessions.startSignIn('owner', [
          'claude',
          'auth',
          'login',
        ]);
        await pumpEventQueue();
        expect(shell.state, LocalShellState.running, reason: reason);
        expect(android.calls, contains('enable'));
        await sessions.endSignIn(shell);
        expect(android.running, isFalse, reason: 'released after the sign-in');
        android.calls.clear();
      }
    },
  );

  test('a running sign-in says what stopped its service', () async {
    var shell = sessions.startSignIn('owner', ['claude', 'auth', 'login']);
    await pumpEventQueue();
    expect(shell.state, LocalShellState.running);
    android.controller.handleNativeTimeout({
      'reason': 'systemTimeout',
      'backgroundPause': _pause(paused: true, reason: 'timeLimit'),
    });
    await pumpEventQueue();
    expect(shell.failure, endsWith('Code: sign-in-lost/android-time-limit'));

    android.pause = _pause();
    shell = sessions.startSignIn('owner', ['claude', 'auth', 'login']);
    await pumpEventQueue();
    expect(shell.state, LocalShellState.running);
    android.running = false;
    await android.controller.refreshStatus();
    await pumpEventQueue();
    expect(shell.failure, '$_words\nCode: sign-in-lost/service-gone');
  });
}
