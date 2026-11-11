import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/domain/models.dart';
import 'support/offline_queue_fixtures.dart';

/// A server that already holds [seen] in the conversation.
class _SeenApi extends FakeApi {
  _SeenApi(this.seen);
  final List<MessageWithParts> seen;

  @override
  Future<List<MessageWithParts>> messages(String id) async => seen;
}

MessageWithParts _prompt(String text) => MessageWithParts(
  info: MessageInfo(
    id: 'm1',
    sessionID: 'session-1',
    role: 'user',
    time: MsgTime(created: 5000),
  ),
  parts: [Part(type: 'text', text: text)],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (_) async => null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('oc/background'),
          (_) async => null,
        );
  });

  testWidgets('a prompt the conversation already shows is not also waiting', (
    tester,
  ) async {
    final api = _SeenApi([_prompt('say killed')]);
    final controller = await queueController(api);
    addTearDown(controller.dispose);
    await controller.queuePrompt(
      queuedEntry('q1', text: 'say killed', dispatchedAt: 1700000000000),
    );
    await pumpChat(tester, controller);
    await tester.pumpAndSettle();

    expect(find.text('say killed'), findsOneWidget);
    expect(find.byKey(const ValueKey('queued-send-0')), findsNothing);
    expect(controller.queuedPromptsFor('session-1'), isEmpty);
  });

  testWidgets('an unconfirmed prompt stays waiting when it is not shown', (
    tester,
  ) async {
    final api = _SeenApi([_prompt('something else')]);
    final controller = await queueController(api);
    addTearDown(controller.dispose);
    await controller.queuePrompt(
      queuedEntry('q1', text: 'say killed', dispatchedAt: 1700000000000),
    );
    await pumpChat(tester, controller);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('queued-send-0')), findsOneWidget);
    expect(controller.queuedPromptsFor('session-1'), hasLength(1));
  });

  testWidgets('an unconfirmed prompt is not restored into the composer too', (
    tester,
  ) async {
    final api = FakeApi();
    final controller = await queueController(api);
    addTearDown(controller.dispose);
    await controller.queuePrompt(
      queuedEntry('q1', text: 'say killed', dispatchedAt: 1700000000000),
    );
    await controller.saveSessionDraft(
      'session-1',
      'say killed',
      profileID: 'profile-1',
    );
    await pumpChat(tester, controller);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('queued-send-0')), findsOneWidget);
    final field = tester.widget<EditableText>(find.byType(EditableText).last);
    expect(field.controller.text, isEmpty);
  });

  resendTests();

  testWidgets('other draft text is still restored', (tester) async {
    final api = FakeApi();
    final controller = await queueController(api);
    addTearDown(controller.dispose);
    await controller.queuePrompt(
      queuedEntry('q1', text: 'say killed', dispatchedAt: 1700000000000),
    );
    await controller.saveSessionDraft(
      'session-1',
      'a different thought',
      profileID: 'profile-1',
    );
    await pumpChat(tester, controller);
    await tester.pumpAndSettle();

    final field = tester.widget<EditableText>(find.byType(EditableText).last);
    expect(field.controller.text, 'a different thought');
  });
}

/// A server that only holds the conversation once the prompt has arrived,
/// the way it does after an explicit resend of an unconfirmed send.
class _ArrivesOnSend extends FakeApi {
  @override
  Future<List<MessageWithParts>> messages(String id) async => prompts.isEmpty
      ? []
      : [
          _prompt('cut2'),
          MessageWithParts(
            info: MessageInfo(
              id: 'm2',
              sessionID: 'session-1',
              role: 'assistant',
              time: MsgTime(created: 5001),
            ),
            parts: [Part(type: 'text', text: 'the live reply')],
          ),
        ];
}

void resendTests() {
  testWidgets('M2: a successful explicit resend clears the card and shows the '
      'prompt and reply without reopening the chat', (tester) async {
    final api = _ArrivesOnSend();
    final controller = await queueController(api);
    addTearDown(controller.dispose);
    await controller.queuePrompt(
      queuedEntry('q1', text: 'cut2', dispatchedAt: 1700000000000),
    );
    await pumpChat(tester, controller);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('queued-send-0')), findsOneWidget);
    expect(find.text('the live reply'), findsNothing);

    await openQueuedAction(tester, 'queued-action-resend');
    await tester.tap(find.widgetWithText(FilledButton, 'Send again'));
    await tester.pumpAndSettle();
    await settleWidgets(tester, () => controller.queuedPromptCount == 0);
    await tester.pumpAndSettle();

    expect(api.prompts, hasLength(1));
    expect(find.byKey(const ValueKey('queued-send-0')), findsNothing);
    expect(find.text('cut2'), findsOneWidget);
    expect(find.text('the live reply'), findsOneWidget);
  });
}
