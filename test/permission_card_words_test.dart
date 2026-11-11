// The permission card describes the real request in plain words: the ask for
// every kind it renders, and for an ask to work outside the project, what the
// call does there (read, write, run) and the exact path it touches.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/domain/models.dart';
import 'package:agentphone/l10n/app_localizations.dart';
import 'package:agentphone/l10n/app_localizations_ar.dart';
import 'package:agentphone/l10n/app_localizations_en.dart';
import 'package:agentphone/ui/kit/kit_request_card.dart';
import 'package:agentphone/ui/permission_presentation.dart';
import 'package:agentphone/ui/screens/chat/permission_sheet.dart';

void main() {
  final en = AppLocalizationsEn();

  String ask(String permission, {String? tool}) => permissionRequestQuestion(
    permission,
    fallback: permissionRequestTitle(permission, l10n: en),
    l10n: en,
    toolName: tool,
  );

  test('every kind the card renders asks its own plain question', () {
    expect(ask('bash'), 'Run this command?');
    expect(ask('edit'), 'Edit this file?');
    expect(ask('write'), 'Edit this file?');
    expect(ask('read'), 'Read this file?');
    expect(ask('webfetch'), 'Open this web page?');
    expect(ask('websearch'), en.chatRequestTitleWebSearch);
    expect(ask('task'), en.chatRequestTitleTask);
    expect(ask('doom_loop'), en.e7PermissionAction5);
  });

  test('outside the project: the question names what the call does', () {
    expect(
      ask('external_directory', tool: 'write'),
      'Write outside this project?',
    );
    expect(
      ask('external_directory', tool: 'edit'),
      'Write outside this project?',
    );
    expect(
      ask('external_directory', tool: 'read'),
      'Read outside this project?',
    );
    expect(
      ask('external_directory', tool: 'grep'),
      'Read outside this project?',
    );
    expect(
      ask('external_directory', tool: 'bash'),
      'Run a command outside this project?',
    );
    expect(ask('external_directory'), 'Work outside this project?');
    expect(
      ask('external_directory', tool: 'mystery'),
      'Work outside this project?',
    );
    expect(ask('external_directory', tool: 'write'), isNot(contains('folder')));
  });

  test('the Arabic asks say the same, with no leftover English', () {
    final ar = AppLocalizationsAr();
    for (final words in [
      ar.chatRequestAskDirectory,
      ar.chatRequestAskOutsideWrite,
      ar.chatRequestAskOutsideRead,
      ar.chatRequestAskOutsideRun,
    ]) {
      expect(words, matches(RegExp(r'^[؀-ۿ\s؟]+$')));
    }
  });

  Future<KitRequestCard> card(
    WidgetTester tester,
    PermissionRequest request, {
    String? toolName,
    String? target,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => permissionRequestCard(
              context,
              permission: request,
              who: 'OpenCode',
              onAllow: () {},
              onReject: () {},
              toolName: toolName,
              target: target,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return tester.widget<KitRequestCard>(find.byType(KitRequestCard));
  }

  PermissionRequest outside() => PermissionRequest(
    id: 'per_1',
    sessionID: 'ses_1',
    permission: 'external_directory',
    patterns: const ['/etc/*'],
  );

  testWidgets('a write outside the project shows the file, not the folder', (
    tester,
  ) async {
    final shown = await card(
      tester,
      outside(),
      toolName: 'write',
      target: '/etc/x',
    );
    expect(shown.title, 'Write outside this project?');
    expect(shown.summary, '/etc/x');
    expect(find.text('Open this folder?'), findsNothing);
  });

  testWidgets('an outside ask with no known tool says so plainly', (
    tester,
  ) async {
    final shown = await card(tester, outside());
    expect(shown.title, 'Work outside this project?');
    expect(shown.summary, '/etc/*');
  });

  testWidgets('a command outside the project says run, with the command', (
    tester,
  ) async {
    final shown = await card(
      tester,
      outside(),
      toolName: 'bash',
      target: 'ls /etc',
    );
    expect(shown.title, 'Run a command outside this project?');
    expect(shown.summary, 'ls /etc');
  });
}
