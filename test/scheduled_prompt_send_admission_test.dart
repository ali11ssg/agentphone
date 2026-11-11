import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/domain/models.dart';
import 'package:agentphone/domain/server_gateway.dart';
import 'package:agentphone/platform/platform_capabilities.dart';
import 'package:agentphone/scheduling/platform.dart';
import 'package:agentphone/state/connection.dart';
import 'package:agentphone/state/offline_queue.dart';
import 'package:agentphone/state/profiles.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_server_gateway.dart';

class _Gateway extends FakeServerGateway {
  _Gateway() : super(baseUrl: 'http://127.0.0.1:4097');
  int sends = 0;

  @override
  Future<Session> session(String sessionID) async => Session(id: sessionID);

  @override
  ServerCapabilities get capabilities =>
      const ServerCapabilities(offlinePromptQueue: true);

  @override
  Future<void> promptAsync(
    String sessionID, {
    required String text,
    ModelRef? model,
    String? agent,
    String? variant,
    List<PromptAttachment> attachments = const [],
    List<PromptAgentMention> agentMentions = const [],
    PromptDelivery? delivery,
  }) async {
    sends++;
  }
}

class _Controller extends ConnectionController {
  _Controller(super.store, this.target);
  ServerProfile target;

  @override
  ServerProfile get profile => target;

  @override
  Future<ServerGateway?> prepareActionTransport() async => api;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late _Controller controller;
  late _Gateway gateway;
  var checks = 0;
  var leased = true;

  setUp(() async {
    debugPlatformCapabilities = const PlatformCapabilities.android();
    SharedPreferences.setMockInitialValues({});
    checks = 0;
    leased = true;
    messenger.setMockMethodCallHandler(ScheduledPromptsPlatform.channel, (
      call,
    ) async {
      if (call.method == 'activePhoneLease') {
        checks++;
        return leased;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (_) async => null,
    );
    gateway = _Gateway();
    controller =
        _Controller(
            ProfileStore(prefs: await SharedPreferences.getInstance()),
            ServerProfile(
              id: 'phone',
              name: 'Phone',
              baseUrl: 'http://127.0.0.1:4097',
              flavor: ServerFlavor.v2,
            ),
          )
          ..api = gateway
          ..status = StreamStatus.connected;
  });

  tearDown(() {
    controller.dispose();
    debugPlatformCapabilities = null;
    messenger.setMockMethodCallHandler(ScheduledPromptsPlatform.channel, null);
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
  });

  Future<void> composerSend() async {
    await controller.waitForSessionSelection('session', expectedApi: gateway);
    await gateway.promptAsync('session', text: 'interactive');
  }

  test(
    'composer cannot start work on a leased phone; release permits send',
    () async {
      await expectLater(composerSend(), throwsA(isA<ProductException>()));
      expect(gateway.sends, 0);
      leased = false;
      await composerSend();
      expect(gateway.sends, 1);
      expect(checks, 2);
    },
  );

  test(
    'unavailable check fails closed without claiming an active lease',
    () async {
      messenger.setMockMethodCallHandler(
        ScheduledPromptsPlatform.channel,
        (_) async => throw PlatformException(code: 'unavailable'),
      );
      await expectLater(
        composerSend(),
        throwsA(
          isA<ProductException>().having(
            (error) => error.message,
            'friendly error',
            'The phone server could not be checked. Try again.',
          ),
        ),
      );
      expect(gateway.sends, 0);
    },
  );

  test(
    'connection change while native check waits prevents dispatch',
    () async {
      final answer = Completer<bool>();
      final entered = Completer<void>();
      messenger.setMockMethodCallHandler(ScheduledPromptsPlatform.channel, (_) {
        entered.complete();
        return answer.future;
      });
      final send = composerSend();
      final rejected = expectLater(send, throwsA(isA<ProductException>()));
      await entered.future;
      controller.api = null;
      answer.complete(false);
      await rejected;
      expect(gateway.sends, 0);
    },
  );

  test('remote agents and non-Android do not query phone lease', () async {
    controller.target = ServerProfile(
      id: 'remote',
      name: 'Remote',
      baseUrl: 'wss://example.test',
      backend: ServerBackend.codex,
    );
    await composerSend();
    controller.target = ServerProfile(
      id: 'local',
      name: 'Desktop',
      baseUrl: 'http://127.0.0.1:4097',
      flavor: ServerFlavor.v2,
    );
    debugPlatformCapabilities = const PlatformCapabilities.linuxDesktop();
    await composerSend();
    expect(gateway.sends, 2);
    expect(checks, 0);
  });

  test(
    'queued prompt stays unsent and retryable while phone is leased',
    () async {
      await controller.queuePrompt(
        const QueuedPrompt(
          id: 'queued',
          profileID: 'phone',
          sessionID: 'session',
          text: 'queued interactive',
          createdAt: 1,
        ),
      );
      await controller.retryQueuedPrompt('queued');
      expect(gateway.sends, 0);
      final waiting = controller.queuedPromptsFor('session').single;
      expect(waiting.dispatched, isFalse);
      expect(waiting.error, contains('scheduled prompt'));
      leased = false;
      await controller.retryQueuedPrompt('queued');
      expect(gateway.sends, 1);
      expect(controller.queuedPromptsFor('session'), isEmpty);
    },
  );
}
