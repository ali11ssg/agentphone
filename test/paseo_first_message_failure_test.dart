// A Claude Code chat that cannot start says why under Details.
//
// Owner's phone, build 2515: New conversation → Claude Code → first message
// showed "Could not start this chat. Refresh before trying again." on every
// try. A draft row appeared, the daemon never received or kept an agent, and
// neither the screen nor the problem report named the cause: the start
// wrapped it, and the wrapped cause's own details (the host's refusal, the
// daemon's sentence) were dropped on the way to Details.
import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/domain/product_failure.dart';
import 'package:agentphone/domain/server_gateway.dart';
import 'package:agentphone/paseo/chat_feed_source.dart';
import 'package:agentphone/paseo/gateway.dart';
import 'package:agentphone/paseo/transport.dart';

import 'paseo_acp_pilot_test.dart' show FakePaseoSocket;

const _directory = '/root/projects/FinanceHub3';

/// The fake daemon as Paseo 0.11.2 answers: Claude ready with its modes.
FakePaseoSocket _daemon() {
  final socket = FakePaseoSocket();
  socket.handlers['fetch_agents_request'] = (_) => (
    'fetch_agents_response',
    {
      'entries': <Object>[],
      'pageInfo': {'hasMore': false, 'nextCursor': null, 'prevCursor': null},
    },
  );
  socket.handlers['get_providers_snapshot_request'] = (_) => (
    'get_providers_snapshot_response',
    {
      'entries': [
        {
          'provider': 'claude',
          'status': 'ready',
          'enabled': true,
          'models': [
            {'id': 'claude-opus-5-5', 'label': 'Opus 5.5', 'isDefault': true},
          ],
          'modes': [
            {'id': 'default'},
            {'id': 'acceptEdits'},
            {'id': 'plan'},
          ],
          'defaultModeId': 'default',
        },
      ],
    },
  );
  return socket;
}

PaseoGateway _gateway(
  FakePaseoSocket socket, {
  Future<void> Function()? beforePayloadUse,
}) => PaseoGateway(
  directory: _directory,
  defaultProviderModes: const {'claude': 'default'},
  trackLocalWork: true,
  beforePayloadUse: beforePayloadUse,
  afterPayloadUse: beforePayloadUse == null ? null : () {},
  transport: PaseoTransport(
    endpoint: 'ws://127.0.0.1:4099/ws',
    socketFactory: (_, _) async => socket,
  ),
);

Future<ProductException> _startFails(PaseoChatFeedSource source) async {
  try {
    await source.startAgentChatIn(
      _directory,
      agentId: 'claude',
      firstPrompt: 'reply with the word ready',
      modelId: 'claude-opus-5-5',
    );
  } on ProductException catch (error) {
    return error;
  }
  fail('The chat started.');
}

void main() {
  test('a host that refuses new work names its reason under Details', () async {
    final socket = _daemon();
    // The phone host refuses while its own setup work runs (BuiltinPhoneAgents
    // ._beginPayloadUse): app-authored words, never native text.
    final gateway = _gateway(
      socket,
      beforePayloadUse: () async => throw const ProductException(
        'Agent setup is in progress. Wait for it to finish and try again.',
        cause: 'phone check running',
      ),
    );
    final source = PaseoChatFeedSource(gateway);
    addTearDown(() async {
      await source.dispose();
      gateway.close();
      await socket.close();
    });

    final error = await _startFails(source);

    expect(
      error.message,
      'Could not start this chat. Refresh before trying again.',
    );
    // Nothing reached the daemon, and the failed start left no draft row.
    expect(socket.of('create_agent_request'), isEmpty);
    await source.refreshChatFeed();
    expect(source.chatFeed().items, isEmpty);
    // What it never said: why.
    final details = ProductFailure.from(error).technicalDetails;
    expect(details, contains('Agent setup is in progress'));
    expect(details, contains('phone check running'));
  });

  test(
    'a daemon that refuses the agent names its sentence under Details',
    () async {
      final socket = _daemon();
      // Paseo 0.11.2 answers a refused create with a status push
      // (session.js handleCreateAgentRequest → agent_create_failed).
      socket.handlers['create_agent_request'] = (request) => (
        'status',
        {
          'status': 'agent_create_failed',
          'error':
              'Working directory does not exist or is not a directory: $_directory',
          'errorCode': 'unknown',
        },
      );
      final gateway = _gateway(socket);
      final source = PaseoChatFeedSource(gateway);
      addTearDown(() async {
        await source.dispose();
        gateway.close();
        await socket.close();
      });

      final error = await _startFails(source);

      final create = socket.of('create_agent_request').single;
      expect((create['config'] as Map)['provider'], 'claude');
      expect((create['config'] as Map)['model'], 'claude-opus-5-5');
      expect((create['config'] as Map)['modeId'], 'default');
      expect(create['initialPrompt'], 'reply with the word ready');
      // The refused start left no "New conversation" row behind.
      await source.refreshChatFeed();
      expect(source.chatFeed().items, isEmpty);
      expect(
        ProductFailure.from(error).technicalDetails,
        contains('Working directory does not exist'),
      );
    },
  );
}
