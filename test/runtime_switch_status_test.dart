// While the app switches this phone's own server between OpenCode versions
// the header names the version being switched to, in one calm progress
// state: never "Reconnecting to … OpenCode 2", "Server password changed" or
// "isn't answering" for the server it is deliberately leaving.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/domain/connection_status.dart';
import 'package:agentphone/ui/app_theme.dart';

import '../tool/capture/fixtures.dart' show loadCaptureFonts;
import 'support/runtime_switch_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadCaptureFonts);

  late RuntimeSwitchShell shell;

  setUp(() async => shell = await RuntimeSwitchShell.create());

  Future<void> pumpShell(WidgetTester tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(shell.app(theme: AppTheme.dark()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> tearDownShell(WidgetTester tester) async {
    if (shell.starter.starting) shell.linux.finish();
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    shell.dispose();
  }

  Finder pill(String text) => find.descendant(
    of: find.byKey(const ValueKey('server-switcher-button')),
    matching: find.textContaining(text),
  );

  Finder line() => find.byKey(const ValueKey('connection-status-banner'));

  testWidgets('a plain reconnect is said once too; a real problem keeps its '
      'line and its action', (tester) async {
    await pumpShell(tester);
    // Restarting the same server is no switch: it reconnects, said by the
    // pill alone.
    unawaited(shell.starter.start(phoneTwo));
    await settle(tester);
    expect(pill('Reconnecting'), findsOneWidget);
    expect(pill('Switching'), findsNothing);
    expect(line(), findsNothing);
    shell.linux.finish();
    await settle(tester);
    shell.controller.show(ConnectionStatusPhase.connecting);
    await settle(tester);
    expect(pill('Connecting'), findsOneWidget);
    expect(line(), findsNothing);
    // Not answering needs the person: the line comes back with its act.
    shell.controller.show(ConnectionStatusPhase.notAnswering);
    await settle(tester);
    expect(line(), findsOneWidget);
    expect(
      find.descendant(of: line(), matching: find.byType(TextButton)),
      findsWidgets,
    );
    shell.controller.show(ConnectionStatusPhase.credentialsRequired);
    await settle(tester);
    expect(
      find.textContaining('changed. Update it to reconnect.'),
      findsOneWidget,
    );
    await tearDownShell(tester);
  });
}
