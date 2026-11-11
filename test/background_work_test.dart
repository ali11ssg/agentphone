import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/domain/models.dart';
import 'package:agentphone/domain/product_repository.dart';
import 'package:agentphone/api2/client.dart';
import 'package:agentphone/api2/gateway_operations.dart';
import 'package:agentphone/domain/background_work.dart';

import 'support/v2_subagent_fixture.dart';

import 'api2_interaction_gateway_test.dart' show withServer, writeNoContent;

MessageWithParts work(
  String name, {
  String status = 'running',
  bool background = false,
  bool completed = false,
}) => MessageWithParts(
  info: MessageInfo(
    id: 'msg_a',
    sessionID: 'ses_a',
    role: 'assistant',
    time: MsgTime(created: 1, completed: completed ? 2 : null),
  ),
  parts: [
    Part(
      type: 'tool',
      toolName: name,
      toolState: ToolState.fromJson({
        'status': status,
        'input': <String, dynamic>{},
        'metadata': {'background': background},
      }),
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('only supported foreground work is eligible', () {
    final messages = [
      work('task'),
      work('shell'),
      work('bash'),
      work('pty'),
      work('task', background: true),
      work('task', status: 'completed'),
      work('task', completed: true),
    ];
    expect(
      foregroundBackgroundableParts(
        messages,
        BackgroundWorkSupport.unavailable,
      ),
      isEmpty,
    );
    expect(
      foregroundBackgroundableParts(
        messages,
        BackgroundWorkSupport.subagents,
      ).map((part) => part.toolName),
      ['task'],
    );
    expect(
      foregroundBackgroundableParts(
        messages,
        BackgroundWorkSupport.subagentsAndShells,
      ).map((part) => part.toolName),
      ['task', 'shell'],
    );
  });

  test(
    'native v2 foreground progress is eligible without treating progress as detachment',
    () {
      MessageWithParts native(ToolState state) => MessageWithParts(
        info: MessageInfo(
          id: 'msg_v2',
          sessionID: 'ses_parent',
          role: 'assistant',
        ),
        parts: [Part(type: 'tool', toolName: 'subagent', toolState: state)],
      );
      final foreground = native(
        v2SubagentState(status: 'running', background: false),
      );
      final variants = [
        foreground,
        native(v2SubagentState(status: 'running')),
        native(v2SubagentState(status: 'streaming', background: false)),
        native(v2SubagentState()),
        native(v2SubagentState(childStatus: 'completed', background: false)),
        native(
          v2SubagentState(
            status: 'running',
            background: false,
            executed: false,
          ),
        ),
        native(v2SubagentState(status: 'error', background: false)),
      ];
      expect(
        foregroundBackgroundableParts(
          variants,
          BackgroundWorkSupport.subagentsAndShells,
        ),
        [foreground.parts.single],
      );
      expect(
        foregroundBackgroundableParts(
          variants,
          BackgroundWorkSupport.subagents,
        ),
        isEmpty,
      );
      expect(
        foregroundBackgroundableParts(
          variants,
          BackgroundWorkSupport.unavailable,
        ),
        isEmpty,
      );
    },
  );

  test('v2 204 acknowledges a request without claiming promotion', () async {
    await withServer(
      handler: (request) async {
        expect(request.method, 'POST');
        expect(request.uri.path, '/api/session/ses_a/background');
        await writeNoContent(request);
      },
      (server, requests) async {
        final client = Api2Client.connect(
          baseUrl: 'http://${server.address.host}:${server.port}',
          password: 'test-password',
          directory: '/work',
          workspace: 'ws_a',
        );
        addTearDown(client.close);
        final repo = Api2OperationsGateway(client: client);
        expect(
          await repo.loadBackgroundWorkSupport(),
          BackgroundWorkSupport.subagentsAndShells,
        );
        expect(
          await repo.backgroundSession('ses_a'),
          BackgroundWorkResult.requested,
        );
        expect(
          requests.single.uri.queryParameters['location[directory]'],
          '/work',
        );
        expect(
          requests.single.uri.queryParameters['location[workspace]'],
          'ws_a',
        );
      },
    );
  });
}
