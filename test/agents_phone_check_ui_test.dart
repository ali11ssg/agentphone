import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/domain/agent_catalog.dart';
import 'package:agentphone/domain/phone_agent_host.dart';
import 'package:agentphone/domain/phone_agents.dart';
import 'package:agentphone/domain/phone_agents_source.dart';
import 'package:agentphone/ui/kit/kit.dart';
import 'package:agentphone/ui/screens/agents/agent_sheet.dart';
import 'package:agentphone/ui/screens/agents/agents_section.dart';
import 'package:agentphone/ui/screens/agents/phone_check_view.dart';

import '../tool/capture/fixtures.dart' show loadCaptureFonts;
import 'support/agents_fakes.dart';
import 'support/chats_fakes.dart';
import 'support/fake_server_capabilities.dart';

class _RecoverableAgents extends FakePhoneAgentsSource
    implements PhoneAgentRecoverySource {
  _RecoverableAgents()
    : super(rows: [agentRowFor('claude', FakeAgentStage.needsCheck)]);

  Completer<AgentPhoneCheckResult>? pending;

  @override
  Future<AgentPhoneCheckResult> runAgentPhoneCheck(String agentId) =>
      pending?.future ?? super.runAgentPhoneCheck(agentId);

  @override
  Future<AgentPhoneCheckResult> usePreviousAgentVersion(String agentId) async {
    calls.add('previous:$agentId');
    return nextCheck!;
  }
}

AgentPhoneCheckResult _failure(AgentHostFailure failure, {String? previous}) =>
    AgentPhoneCheckResult(
      agentId: 'claude',
      architecture: AgentArchitecture.arm64,
      passed: false,
      completed: const [
        AgentPhoneCheckStep.install,
        AgentPhoneCheckStep.version,
        AgentPhoneCheckStep.daemon,
      ],
      failure: failure,
      previousVersion: previous,
      details: 'Paseo expected 0.11.2; observed 0.9.2',
    );

Future<void> _sheet(WidgetTester tester, _RecoverableAgents agents) async {
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final host = FakeChatsHost(FakeChatFeedSource())..phoneAgents = agents;
  await tester.pumpWidget(
    chatsApp(
      host,
      const AgentSheet(agentId: 'claude', step: AgentSheetStep.check),
    ),
  );
  await tester.pump();
  if (agents.pending == null) await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadCaptureFonts);

  testWidgets('Paseo failure explains the connection and hides details', (
    tester,
  ) async {
    final agents = _RecoverableAgents()
      ..nextCheck = _failure(AgentHostFailure.hello);
    await _sheet(tester, agents);
    expect(
      find.textContaining('Paseo did not confirm the connection.'),
      findsOneWidget,
    );
    expect(
      find.textContaining("The agent started but didn't answer"),
      findsNothing,
    );
    expect(find.text('Try again'), findsOneWidget);
    expect(find.textContaining('Paseo expected 0.11.2'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('agents-check-details')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Paseo expected 0.11.2'), findsOneWidget);
  });

  testWidgets('signed-out check offers the sign-in flow', (tester) async {
    final agents = _RecoverableAgents()
      ..nextCheck = _failure(AgentHostFailure.needsSignIn);
    await _sheet(tester, agents);
    expect(
      find.textContaining('Sign in to your Claude account to use it.'),
      findsOneWidget,
    );
    // A normal signed-out phone is not a failed check.
    expect(find.textContaining("didn't pass the check"), findsNothing);
    expect(
      find.textContaining('Claude Code is installed. Sign in'),
      findsOneWidget,
    );
    final marks = tester
        .widgetList<KitTaskMark>(find.byType(KitTaskMark))
        .map((mark) => mark.state);
    expect(marks, isNot(contains(KitTaskState.failed)));
    expect(find.byKey(const ValueKey('agents-check-details')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('agents-check-again')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('agents-sign-in-start')), findsOneWidget);
    expect(agents.calls.where((call) => call == 'check:claude'), hasLength(1));
  });

  testWidgets('helper update action runs the complete phone check', (
    tester,
  ) async {
    final agents = _RecoverableAgents()
      ..nextCheck = _failure(AgentHostFailure.helperVersion);
    await _sheet(tester, agents);
    expect(find.text('Update Paseo and try again'), findsOneWidget);
    await tester.tap(find.text('Update Paseo and try again'));
    await tester.pumpAndSettle();
    expect(agents.calls.where((call) => call == 'check:claude'), hasLength(2));
  });

  testWidgets(
    'rollback is offered only when the host found a previous version',
    (tester) async {
      final agents = _RecoverableAgents()
        ..nextCheck = _failure(AgentHostFailure.hello, previous: '2.1.283');
      await _sheet(tester, agents);
      expect(find.textContaining('2.1.283'), findsOneWidget);
      await tester.tap(find.text('Use the previous version'));
      await tester.pumpAndSettle();
      expect(agents.calls, contains('previous:claude'));
    },
  );

  testWidgets('missing previous version has no rollback action', (
    tester,
  ) async {
    final agents = _RecoverableAgents()
      ..nextCheck = _failure(AgentHostFailure.hello);
    await _sheet(tester, agents);
    expect(find.text('Use the previous version'), findsNothing);
  });

  testWidgets('running check shows resumed bytes and real progress', (
    tester,
  ) async {
    final agents = _RecoverableAgents()
      ..pending = Completer<AgentPhoneCheckResult>()
      ..progress = const AgentSetupProgress(
        agentId: 'claude',
        phase: AgentSetupPhase.installing,
        componentId: 'agent-claude',
        downloadedBytes: 60000000,
        totalBytes: 240000000,
        checkStep: AgentPhoneCheckStep.install,
      );
    await _sheet(tester, agents);
    expect(find.textContaining('60 MB'), findsOneWidget);
    expect(find.textContaining('240 MB'), findsOneWidget);
    expect(find.byKey(const ValueKey('agents-check-download')), findsOneWidget);
    agents.change(
      () => agents.progress = const AgentSetupProgress(
        agentId: 'claude',
        phase: AgentSetupPhase.done,
        checkStep: AgentPhoneCheckStep.hello,
      ),
    );
    await tester.pump();
    final view = tester.widget<AgentPhoneCheckView>(
      find.byType(AgentPhoneCheckView),
    );
    expect(view.progress!.checkStep, AgentPhoneCheckStep.hello);
    final installed = find.descendant(
      of: find.byKey(const ValueKey('agents-check-install')),
      matching: find.byType(KitTaskMark),
    );
    expect(tester.widget<KitTaskMark>(installed).state, KitTaskState.done);
    expect(find.byKey(const ValueKey('agents-check-download')), findsNothing);
  });

  testWidgets('Settings phone check shows matching live download progress', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final agents = _RecoverableAgents()
      ..pending = Completer<AgentPhoneCheckResult>()
      ..progress = const AgentSetupProgress(
        agentId: 'claude',
        phase: AgentSetupPhase.installing,
        componentId: 'agent-claude',
        downloadedBytes: 60000000,
        totalBytes: 240000000,
        checkStep: AgentPhoneCheckStep.install,
      );
    final host = FakeChatsHost(FakeChatFeedSource())..phoneAgents = agents;
    await tester.pumpWidget(
      chatsApp(host, const SingleChildScrollView(child: AgentsSection())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agents-check-phone')));
    await tester.pump();
    expect(find.textContaining('60 MB'), findsOneWidget);
    expect(find.textContaining('240 MB'), findsOneWidget);
    agents.change(
      () => agents.progress = const AgentSetupProgress(
        agentId: 'claude',
        phase: AgentSetupPhase.installing,
        componentId: 'agent-claude',
        downloadedBytes: 120000000,
        totalBytes: 240000000,
        checkStep: AgentPhoneCheckStep.install,
      ),
    );
    await tester.pump();
    expect(find.textContaining('120 MB'), findsOneWidget);
    agents.change(
      () => agents.progress = const AgentSetupProgress(
        agentId: 'codex',
        phase: AgentSetupPhase.installing,
        downloadedBytes: 120000000,
        totalBytes: 240000000,
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('agents-check-download')), findsNothing);
  });

  testWidgets('a real version change explains why another check is needed', (
    tester,
  ) async {
    final agents = _RecoverableAgents()
      ..pending = Completer<AgentPhoneCheckResult>()
      ..rows = [
        buildAgentRow(
          descriptor: AgentCatalog.builtIn.byId('claude')!,
          architecture: AgentArchitecture.arm64,
          serverCapabilities: testServerCapabilities,
          runtime: const PhoneAgentRuntime(
            agentId: 'claude',
            installed: true,
            checkRequiredReason: 'agentVersion',
          ),
        ),
      ];
    await _sheet(tester, agents);
    expect(
      find.text('The required agent version changed. Check this phone again.'),
      findsOneWidget,
    );
  });
}
