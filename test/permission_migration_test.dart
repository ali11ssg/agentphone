import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/domain/models.dart';
import 'support/fake_server_gateway.dart';
import 'package:agentphone/state/connection.dart';
import 'package:agentphone/state/profiles.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _HydrationApi extends FakeServerGateway {
  _HydrationApi() : super(baseUrl: 'http://localhost');

  int failuresRemaining = 1;
  int calls = 0;
  List<PermissionRequest> result = [];

  @override
  Future<List<PermissionRequest>> pendingPermissions() async {
    calls += 1;
    if (failuresRemaining > 0) {
      failuresRemaining -= 1;
      throw ApiException('temporarily unavailable');
    }
    return result;
  }

  @override
  Future<List<PermissionRequest>> pendingPermissionsV2() =>
      Future.error(ApiException('V2 unavailable', statusCode: 404));
}

class _ReplyApi extends FakeServerGateway {
  _ReplyApi() : super(baseUrl: 'http://localhost');

  final List<
    ({
      String requestID,
      String reply,
      String? legacySessionID,
      String? legacyPermissionID,
    })
  >
  replies = [];

  @override
  Future<void> respondPermission(
    String requestID,
    String reply, {
    String? legacySessionID,
    String? legacyPermissionID,
    String? message,
  }) async {
    replies.add((
      requestID: requestID,
      reply: reply,
      legacySessionID: legacySessionID,
      legacyPermissionID: legacyPermissionID,
    ));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('permission request parses the current contract', () {
    final request = PermissionRequest.fromJson(const {
      'id': 'request-1',
      'sessionID': 'session-1',
      'permission': 'bash',
      'patterns': ['git status', 'git diff'],
      'metadata': {'cwd': '/workspace'},
      'always': ['git *'],
      'tool': {'messageID': 'message-1', 'callID': 'call-1'},
    });

    expect(request.id, 'request-1');
    expect(request.sessionID, 'session-1');
    expect(request.permission, 'bash');
    expect(request.patterns, ['git status', 'git diff']);
    expect(request.metadata, {'cwd': '/workspace'});
    expect(request.always, ['git *']);
    expect(request.tool?.messageID, 'message-1');
    expect(request.tool?.callID, 'call-1');
  });

  test('tool states expose pending raw input and error text', () {
    final pending = ToolState.fromJson(const {
      'status': 'pending',
      'input': {'command': 'partial'},
      'raw': '{"command":"git status',
    });
    final failed = ToolState.fromJson(const {
      'status': 'error',
      'input': {'command': 'git status'},
      'error': 'permission denied',
    });

    expect(pending.inputJson, '{"command":"git status');
    expect(failed.output, 'permission denied');
  });

  test(
    'controller tracks concurrent requests and current session statuses',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = ConnectionController(ProfileStore(prefs: prefs));

      controller.handleEventForTesting(
        EventEnvelope(
          type: 'permission.asked',
          properties: const {
            'id': 'request-1',
            'sessionID': 'session-1',
            'permission': 'bash',
            'patterns': ['git status'],
            'metadata': <String, Object?>{},
            'always': <String>[],
          },
        ),
      );
      controller.handleEventForTesting(
        EventEnvelope(
          type: 'permission.asked',
          properties: const {
            'id': 'request-2',
            'sessionID': 'session-1',
            'permission': 'edit',
            'patterns': ['lib/main.dart'],
            'metadata': <String, Object?>{},
            'always': <String>[],
          },
        ),
      );

      expect(controller.permissions.keys, ['request-1', 'request-2']);
      expect(controller.permissionsForSession('session-1'), hasLength(2));

      controller.handleEventForTesting(
        EventEnvelope(
          type: 'permission.replied',
          properties: const {
            'sessionID': 'session-1',
            'requestID': 'request-1',
            'reply': 'once',
          },
        ),
      );
      expect(controller.permissions.keys, ['request-2']);

      controller.handleEventForTesting(
        EventEnvelope(
          type: 'session.status',
          properties: const {
            'sessionID': 'session-1',
            'status': {'type': 'retry', 'attempt': 1, 'next': 1000},
          },
        ),
      );
      expect(controller.busySessions, contains('session-1'));

      controller.handleEventForTesting(
        EventEnvelope(
          type: 'session.status',
          properties: const {
            'sessionID': 'session-1',
            'status': {'type': 'idle'},
          },
        ),
      );
      expect(controller.busySessions, isNot(contains('session-1')));
    },
  );

  test(
    'controller accepts legacy permission events without losing identity',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final api = _ReplyApi();
      final controller = ConnectionController(ProfileStore(prefs: prefs))
        ..api = api;

      controller.handleEventForTesting(
        EventEnvelope(
          type: 'permission.updated',
          properties: const {
            'id': 'legacy-1',
            'sessionID': 'session-1',
            'type': 'bash',
            'pattern': ['git status', 'git diff'],
            'messageID': 'message-1',
            'callID': 'call-1',
            'metadata': {'cwd': '/workspace'},
          },
        ),
      );
      controller.handleEventForTesting(
        EventEnvelope(
          type: 'permission.updated',
          properties: const {
            'id': 'legacy-2',
            'sessionID': 'session-1',
            'type': 'edit',
            'pattern': 'lib/main.dart',
            'messageID': 'message-2',
            'metadata': <String, Object?>{},
          },
        ),
      );

      expect(controller.permissions.keys, ['legacy-1', 'legacy-2']);
      expect(controller.permissions['legacy-1']?.permission, 'bash');
      expect(controller.permissions['legacy-1']?.patterns, [
        'git status',
        'git diff',
      ]);

      controller.handleEventForTesting(
        EventEnvelope(
          type: 'permission.replied',
          properties: const {
            'sessionID': 'session-1',
            'permissionID': 'legacy-1',
            'response': 'once',
          },
        ),
      );
      await controller.answerPermission('legacy-2', 'always');

      expect(controller.permissions, isEmpty);
      expect(api.replies.single, (
        requestID: 'legacy-2',
        reply: 'always',
        legacySessionID: 'session-1',
        legacyPermissionID: 'legacy-2',
      ));
    },
  );

  testWidgets('pending permission hydration retries transient failures', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final api = _HydrationApi()
      ..result = [
        PermissionRequest.fromJson(const {
          'id': 'request-1',
          'sessionID': 'session-1',
          'permission': 'bash',
          'patterns': ['git status'],
          'metadata': <String, Object?>{},
          'always': <String>[],
        }),
      ];
    final controller = ConnectionController(ProfileStore(prefs: prefs))
      ..api = api;

    await controller.refreshPendingPermissions();
    expect(controller.permissions, isEmpty);

    await tester.pump(const Duration(milliseconds: 251));

    expect(api.calls, 2);
    expect(controller.permissions.keys, ['request-1']);
    controller.dispose();
  });

  test('answering an externally resolved permission is idempotent', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = ConnectionController(ProfileStore(prefs: prefs));
    controller.handleEventForTesting(
      EventEnvelope(
        type: 'permission.asked',
        properties: const {
          'id': 'request-1',
          'sessionID': 'session-1',
          'permission': 'bash',
          'patterns': ['git status'],
          'metadata': <String, Object?>{},
          'always': <String>[],
        },
      ),
    );
    controller.handleEventForTesting(
      EventEnvelope(
        type: 'permission.replied',
        properties: const {'requestID': 'request-1', 'reply': 'once'},
      ),
    );

    await expectLater(
      controller.answerPermission('request-1', 'once'),
      completes,
    );
  });
}
