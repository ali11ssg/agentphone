// End-to-end prompt check against an explicitly selected scratch OC2 server.
// Set OC2_LIVE_PASSWORD and optionally OC2_LIVE_DIR; model auth is required.
import 'dart:async';
import 'dart:io';

import 'package:agentphone/api2/gateway.dart';
import 'package:agentphone/domain/server_gateway.dart';

Future<void> main(List<String> args) async {
  final password = Platform.environment['OC2_LIVE_PASSWORD'];
  if (password == null || password.isEmpty) {
    stderr.writeln('Set OC2_LIVE_PASSWORD for the scratch server.');
    exitCode = 2;
    return;
  }
  final api = Api2Gateway.connect(
    baseUrl: args.isNotEmpty ? args[0] : 'http://127.0.0.1:4097',
    password: password,
    directory: Platform.environment['OC2_LIVE_DIR'],
  );
  String? sessionID;
  LiveEventChannel? stream;
  var sawUser = false;
  var sawAssistant = false;
  var sawSessionEvent = false;
  var failed = false;
  try {
    final health = await api.health();
    stdout.writeln('server v${health.version}');
    final session = await api.createSession();
    sessionID = session.id;
    final connected = Completer<void>();
    stream = api.openEventChannel(
      onStatus: (status) {
        if (status == StreamStatus.connected && !connected.isCompleted) {
          connected.complete();
        }
      },
      onEvent: (event) {
        final properties = event.properties;
        final info = properties['info'];
        final part = properties['part'];
        if (properties['sessionID'] == sessionID ||
            (info is Map && info['sessionID'] == sessionID) ||
            (part is Map && part['sessionID'] == sessionID)) {
          sawSessionEvent = true;
        }
      },
    )..start();
    await connected.future.timeout(const Duration(seconds: 20));
    await api.promptAsync(
      session.id,
      text: 'Reply with exactly: hello from opencode',
    );
    final deadline = DateTime.now().add(const Duration(minutes: 3));
    while (DateTime.now().isBefore(deadline)) {
      final messages = await api.messages(session.id);
      sawUser = messages.any((message) => message.info.role == 'user');
      sawAssistant = messages.any(
        (message) =>
            message.info.role == 'assistant' &&
            message.parts.any(
              (part) => part.type == 'text' && part.text.isNotEmpty,
            ),
      );
      if (sawUser && sawAssistant && sawSessionEvent) break;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  } catch (error) {
    failed = true;
    stderr.writeln('Prompt check failed (${error.runtimeType}).');
  } finally {
    await stream?.dispose();
    final id = sessionID;
    if (id != null) {
      await api.abort(id).catchError((_) {});
      try {
        await api.deleteSession(id);
      } catch (error) {
        failed = true;
        stderr.writeln(
          'Scratch session cleanup failed (${error.runtimeType}).',
        );
      }
    }
    api.close();
  }
  stdout.writeln('user message: $sawUser');
  stdout.writeln('assistant text: $sawAssistant');
  stdout.writeln('session event: $sawSessionEvent');
  final pass = !failed && sawUser && sawAssistant && sawSessionEvent;
  stdout.writeln(pass ? 'PROMPT FLOW PASSED' : 'PROMPT FLOW INCOMPLETE');
  exitCode = pass ? 0 : 1;
}
