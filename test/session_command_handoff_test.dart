import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/domain/product_repository.dart';
import 'package:agentphone/l10n/app_localizations.dart';
import 'package:agentphone/state/connection.dart';
import 'package:agentphone/state/profiles.dart';
import 'package:agentphone/ui/app_theme.dart';
import 'package:agentphone/ui/widgets/session_handoff.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MetadataRepository implements ServerOperationsGateway {
  Session session = Session(
    id: 'session-1',
    projectID: 'project-1',
    directory: '/srv/project',
  );
  int reads = 0;
  @override
  Future<Session> getSessionDetails(String id) async {
    reads++;
    return session;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Controller extends ConnectionController {
  _Controller(super.store, ServerOperationsGateway repo) {
    repository = repo;
  }
  final fixtureProfile = ServerProfile(
    id: 'profile-1',
    name: 'Synthetic server',
    baseUrl: 'https://code.example.test',
    username: 'synthetic-user',
    password: 'synthetic-password-never-copy',
  );
  @override
  ServerProfile get profile => fixtureProfile;
  bool resume = true;
  @override
  ServerCapabilities get capabilities =>
      ServerCapabilities(cliSessionResume: resume);
  @override
  Future<ServerOperationsGateway?> prepareActionRepository() async =>
      repository;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<({_Controller controller, List<String> clipboard})> mount(
    WidgetTester tester,
    _MetadataRepository repository, {
    bool resume = true,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final controller = _Controller(
      ProfileStore(prefs: await SharedPreferences.getInstance()),
      repository,
    )..resume = resume;
    final clipboard = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const secureStorage = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    messenger.setMockMethodCallHandler(secureStorage, (_) async => null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    addTearDown(() {
      controller.dispose();
      messenger.setMockMethodCallHandler(secureStorage, null);
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSessionHandoff(
                context,
                controller: controller,
                sessionID: 'session-1',
                projectID: 'project-1',
              ),
              child: const Text('Continue'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    return (controller: controller, clipboard: clipboard);
  }

  final l10n = lookupAppLocalizations(const Locale('en'));

  // The handoff dialog merged into the one continue-on-computer sheet
  // (slice-P3.11a): the list doors show the same sheet, command and copy
  // as the conversation menu.
  testWidgets('a list door opens the continue-on-computer sheet with the '
      'resume command for the folder the server reports now', (tester) async {
    final repo = _MetadataRepository();
    final fixture = await mount(tester, repo);
    expect(repo.reads, 1);
    expect(find.byKey(const Key('continue-on-computer-sheet')), findsOneWidget);
    // One command: the attach command and the metadata reference are gone.
    expect(find.text(l10n.handoffUiComputerTitle), findsOneWidget);
    expect(find.textContaining('opencode attach'), findsNothing);
    expect(
      find.textContaining('OpenCode session metadata reference'),
      findsNothing,
    );
    final copy = find.byKey(const Key('continue-on-computer-copy'));
    await tester.ensureVisible(copy);
    await tester.pumpAndSettle();
    await tester.tap(copy);
    await tester.pumpAndSettle();
    expect(fixture.clipboard, [
      "cd '/srv/project' && opencode2 --session 'session-1'",
    ]);
    expect(
      fixture.clipboard.single,
      isNot(contains(fixture.controller.profile.password)),
    );
  });

  testWidgets('a conversation in a cloud environment says why there is no '
      'command', (tester) async {
    final repo = _MetadataRepository()
      ..session = Session(
        id: 'session-1',
        projectID: 'project-1',
        directory: '/srv/project',
        workspaceID: 'wrk_managed',
      );
    await mount(tester, repo);
    expect(
      find.byKey(const Key('continue-on-computer-unavailable')),
      findsOneWidget,
    );
    expect(find.text(l10n.handoffUiUnavailableWorkspace), findsOneWidget);
    expect(find.byKey(const Key('continue-on-computer-copy')), findsNothing);
  });

  testWidgets('a conversation that moved project says so instead of a '
      'command for the old place', (tester) async {
    final repo = _MetadataRepository()
      ..session = Session(
        id: 'session-1',
        projectID: 'project-2',
        directory: '/srv/other',
      );
    await mount(tester, repo);
    expect(find.byKey(const Key('continue-on-computer-sheet')), findsNothing);
    expect(find.text(l10n.handoffUiComputerChanged), findsOneWidget);
  });

  testWidgets('a server without CLI resume explains itself and reads '
      'nothing', (tester) async {
    final repo = _MetadataRepository();
    await mount(tester, repo, resume: false);
    expect(repo.reads, 0);
    expect(find.byKey(const Key('continue-on-computer-sheet')), findsNothing);
    expect(find.text(l10n.handoffUiComputerUnsupported), findsOneWidget);
  });
}
