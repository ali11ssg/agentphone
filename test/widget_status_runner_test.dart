import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/domain/models.dart';
import 'package:agentphone/background/widget_action_runner.dart';
import 'package:agentphone/background/widget_status_runner.dart';
import 'package:agentphone/domain/server_gateway.dart';
import 'package:agentphone/state/profiles.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Gateway implements ServerGateway {
  String? status = 'busy';
  String marker = 'user-1';
  bool closed = false;
  String? assistantReply;
  int reads = 0;
  List<PermissionRequest> pending = [];
  Completer<void>? gate;
  void Function()? afterStatus;
  @override
  Future<Health> health() async => Health(healthy: true);
  @override
  Future<List<MessageWithParts>> messages(String id) async => [
    MessageWithParts(
      info: MessageInfo(id: marker, sessionID: id, role: 'user'),
    ),
    if (assistantReply != null)
      MessageWithParts(
        info: MessageInfo(id: 'assistant', sessionID: id, role: 'assistant'),
        parts: [Part(type: 'text', text: assistantReply!)],
      ),
  ];
  @override
  Future<Map<String, String>> sessionStatuses() async {
    reads++;
    await gate?.future;
    afterStatus?.call();
    return {'session': ?status};
  }

  @override
  Future<List<PermissionRequest>> pendingPermissions() async => pending;
  @override
  void close() {
    closed = true;
  }

  // Any mutation or subscription causes the test to fail.
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected ${invocation.memberName}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'run identity excludes OC2 timeline records while retaining real prompts',
    () {
      MessageWithParts message(String id, int created, List<Part> parts) =>
          MessageWithParts(
            info: MessageInfo(
              id: id,
              sessionID: 'session',
              role: 'user',
              time: MsgTime(created: created),
            ),
            parts: parts,
          );
      final prompt = message('user-1', 1, [
        Part(type: 'text', text: 'Synthetic'),
      ]);
      final timeline = [
        for (final (index, type) in [
          'v2:notice',
          'v2:switch',
          'v2:compaction',
          'v2:future',
        ].indexed)
          message('notice-$index', index + 2, [Part(type: type)]),
      ];
      expect(widgetRunMarker([prompt, ...timeline]), 'user-1');
      expect(widgetRunMarker(timeline), isNull);
      // OC1 user parts and attachment-only prompts remain valid identities.
      final next = message('user-2', 10, [
        Part(type: 'file', filename: 'sample.txt'),
      ]);
      expect(widgetRunMarker([prompt, ...timeline, next]), 'user-2');
      expect(widgetRunMarker([message('user-3', 11, [])]), 'user-3');
    },
  );
  final profile = ServerProfile(
    id: 'profile',
    name: 'Server',
    baseUrl: 'http://localhost:4097',
  );
  final fingerprint = widgetProfileFingerprint(profile);
  final ticket = <String, dynamic>{
    'profileID': 'profile',
    'scopeToken': 'scope',
    'sessionID': 'session',
    'fingerprint': fingerprint,
    'runMarker': 'user-1',
    'startedAt': 1,
    'token': 'ticket',
  };
  final target = <String, dynamic>{
    'profileID': 'profile',
    'scopeToken': 'scope',
    'fingerprint': fingerprint,
  };
  int deadline() => DateTime.now().millisecondsSinceEpoch + 1000;
  WidgetStatusRunner runner(
    _Gateway gateway, {
    Future<bool> Function(Map<String, dynamic>)? current,
  }) => WidgetStatusRunner(
    loadProfile: (_) async => profile,
    loadTarget: (_, _) async => target,
    isCurrent: current ?? (_) async => true,
    createTransport: (_, _, _) => WidgetActionTransport(gateway: gateway),
  );
  for (final status in ['busy', 'retry', 'idle', null]) {
    test('one read reports $status and closes without mutations', () async {
      final gateway = _Gateway()..status = status;
      expect(await runner(gateway).check(ticket, deadline()), {
        'status': status == 'busy' || status == 'retry' ? 'busy' : 'idle',
      });
      expect(gateway.reads, 1);
      expect(gateway.closed, isTrue);
    });
  }
  test(
    'idle result includes sanitized assistant reply from existing reads',
    () async {
      final gateway = _Gateway()
        ..status = null
        ..assistantReply = 'Finished password=secret-value';
      expect(await runner(gateway).check(ticket, deadline()), {
        'status': 'idle',
        'preview': 'Finished password=•••',
      });
      expect(gateway.reads, 1);
    },
  );
  test('changed server turn rejects old result before status read', () async {
    final gateway = _Gateway()..marker = 'new-user';
    expect(await runner(gateway).check(ticket, deadline()), {
      'status': 'stale',
    });
    expect(gateway.reads, 0);
    expect(gateway.closed, isTrue);
  });
  test('new turn during read cannot be marked idle', () async {
    final gateway = _Gateway()..status = null;
    gateway.afterStatus = () => gateway.marker = 'new-user';
    expect(await runner(gateway).check(ticket, deadline()), {
      'status': 'stale',
    });
  });
  test('new permission during read never gets cleared', () async {
    final gateway = _Gateway()
      ..status = null
      ..pending = [
        PermissionRequest(id: 'new', sessionID: 'session', permission: 'shell'),
      ];
    expect(await runner(gateway).check(ticket, deadline()), {
      'status': 'stale',
    });
  });
  test(
    'cancellation while status read is pending closes transport and rejects patch',
    () async {
      final gateway = _Gateway()..gate = Completer<void>();
      final run = runner(gateway);
      final result = run.check(ticket, deadline());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      run.cancel();
      gateway.gate!.complete();
      expect(await result, {'status': 'unavailable'});
      expect(gateway.closed, isTrue);
    },
  );
  test('read deadline closes an unresponsive transport', () async {
    final gateway = _Gateway()..gate = Completer<void>();
    expect(
      await runner(
        gateway,
      ).check(ticket, DateTime.now().millisecondsSinceEpoch + 30),
      {'status': 'unavailable'},
    );
    expect(gateway.closed, isTrue);
    expect(gateway.reads, 1);
  });
  test('profile scope changes during read discard idle', () async {
    var current = true;
    final gateway = _Gateway()..status = null;
    gateway.afterStatus = () => current = false;
    expect(
      await runner(
        gateway,
        current: (_) async => current,
      ).check(ticket, deadline()),
      {'status': 'stale'},
    );
  });
  test('stale ticket never opens transport', () async {
    final gateway = _Gateway();
    expect(
      await runner(
        gateway,
        current: (_) async => false,
      ).check(ticket, deadline()),
      {'status': 'stale'},
    );
    expect(gateway.reads, 0);
    expect(gateway.closed, isFalse);
  });

  Map<String, Object> prefsData() => {
    'oc.activeProfile': 'profile',
    'oc.profiles': jsonEncode([profile.toJson()]),
    'oc.widgetFollowup.profile': jsonEncode({'session': ticket}),
    'oc.widgetSessions': jsonEncode({
      'version': 2,
      'profileID': 'profile',
      'scopeToken': 'scope',
      'onDemand': {'fingerprint': fingerprint},
      'sessions': [
        {
          'id': 'session',
          'busy': true,
          'runMarker': 'user-1',
          'startedAt': 1,
          'onDemandActions': [],
        },
      ],
    }),
  };
  test(
    'durable identity permits busy with no buttons but rejects deletion or replacement',
    () async {
      SharedPreferences.setMockInitialValues(prefsData());
      final prefs = await SharedPreferences.getInstance();
      expect(await widgetStatusIsCurrent(prefs, ticket), isTrue);
      await prefs.setString(
        'oc.widgetFollowup.profile',
        jsonEncode({
          'session': {...ticket, 'token': 'new'},
        }),
      );
      expect(await widgetStatusIsCurrent(prefs, ticket), isFalse);
      await prefs.remove('oc.widgetFollowup.profile');
      expect(await widgetStatusIsCurrent(prefs, ticket), isFalse);
    },
  );
  test('profile metadata edits invalidate stored check', () async {
    SharedPreferences.setMockInitialValues(prefsData());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'oc.profiles',
      jsonEncode([
        {...profile.toJson(), 'baseUrl': 'http://edited'},
      ]),
    );
    expect(await widgetStatusIsCurrent(prefs, ticket), isFalse);
  });
}
