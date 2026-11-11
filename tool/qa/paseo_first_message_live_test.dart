// Live probe of the app's "first message starts a Claude Code chat" path
// against a real Paseo daemon. Not part of the suite: run with
//   PASEO_LIVE_URL=ws://127.0.0.1:6795/ws PASEO_LIVE_PASSWORD=... \
//   PASEO_LIVE_DIR=/abs/project flutter test tool/qa/paseo_first_message_live_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/domain/server_gateway.dart' show ProductException;
import 'package:agentphone/paseo/chat_feed_source.dart';
import 'package:agentphone/paseo/gateway.dart';
import 'package:agentphone/paseo/transport.dart';

void main() {
  final env = Platform.environment;
  test(
    'the first message creates the agent in the daemon',
    () async {
      final gateway = PaseoGateway(
        transport: PaseoTransport(
          endpoint: env['PASEO_LIVE_URL']!,
          password: env['PASEO_LIVE_PASSWORD'] ?? '',
          requestTimeout: const Duration(seconds: 15),
        ),
        directory: env['PASEO_LIVE_DIR'],
        // As the phone host opens it.
        defaultProviderModes: const {'claude': 'default'},
        trackLocalWork: true,
      );
      final feed = PaseoChatFeedSource(gateway);
      try {
        final providers = await feed.providers();
        for (final p in providers.providers) {
          stdout.writeln(
            'provider ${p.id} models=${p.modelIDs.take(5).toList()}',
          );
        }
        final id = await feed.startAgentChatIn(
          env['PASEO_LIVE_DIR']!,
          agentId: env['PASEO_LIVE_AGENT'] ?? 'claude',
          firstPrompt: 'reply with the word ready',
          modelId: env['PASEO_LIVE_MODEL'],
        );
        stdout.writeln('started $id');
      } on ProductException catch (error) {
        stdout.writeln('FAILED: ${error.message}');
        stdout.writeln('cause: ${error.cause}');
        rethrow;
      } finally {
        await feed.dispose();
      }
    },
    skip: env['PASEO_LIVE_URL'] == null ? 'needs PASEO_LIVE_URL' : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
