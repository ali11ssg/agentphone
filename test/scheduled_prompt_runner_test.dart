import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/api2/gateway.dart';
import 'package:agentphone/domain/models.dart';
import 'package:agentphone/domain/server_gateway.dart';
import 'package:agentphone/domain/server_trust.dart';
import 'package:agentphone/scheduling/agent_connection.dart';
import 'package:agentphone/scheduling/models.dart';
import 'package:agentphone/scheduling/runner.dart';
import 'package:agentphone/state/profiles.dart';

/// Refuses every request the way the pinned transport does when the
/// server presents a different certificate (or an expired one).
class _TrustRefusingAdapter implements HttpClientAdapter {
  _TrustRefusingAdapter(this.refusal);
  final Exception refusal;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => throw DioException(requestOptions: options, error: refusal);

  @override
  void close({bool force = false}) {}
}

/// Answers OpenCode 2 health and remembers what each request carried.
class _HealthAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      '{"healthy":true,"version":"2.0.28"}',
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _Gateway implements ServerGateway {
  @override
  ServerCapabilities get capabilities =>
      ServerCapabilities(scheduledPrompts: schedulingSupported);
  bool schedulingSupported = true;
  String status = 'idle';
  bool hydrated = false;
  bool coldBusy = false;
  bool closed = false;
  bool failPrompt = false;
  bool completed = false;
  bool needsYou = false;
  int sends = 0;
  int creates = 0;
  String directoryValue = '/project';
  SessionSelection? selection;
  VoidCallback? afterSession;
  VoidCallback? afterPrompt;

  @override
  Future<Health> health() async => Health(healthy: true);
  @override
  Future<Session> session(String id) async {
    hydrated = true;
    if (coldBusy && sends == 0) status = 'busy';
    afterSession?.call();
    return Session(id: id, directory: directoryValue, selection: selection);
  }

  @override
  Future<Session> createSession() async {
    creates++;
    return Session(id: 'created', directory: directoryValue);
  }

  @override
  Future<Map<String, String>> sessionStatuses() async => {
    'existing': status,
    'created': status,
  };
  @override
  Future<List<MessageWithParts>> messages(String id) async => [
    MessageWithParts(
      info: MessageInfo(id: 'old', sessionID: id, role: 'assistant'),
    ),
    if (completed && sends > 0)
      MessageWithParts(
        info: MessageInfo(
          id: 'new',
          sessionID: id,
          role: 'assistant',
          time: MsgTime(completed: 1),
        ),
      ),
  ];
  @override
  Future<List<PermissionRequest>> pendingPermissions() async => [
    if (needsYou)
      PermissionRequest(
        id: 'permission',
        sessionID: 'existing',
        permission: 'shell',
      ),
  ];
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
    expect(delivery, isNull);
    afterPrompt?.call();
    if (failPrompt) {
      throw StateError('private provider response and credential');
    }
  }

  @override
  void close() {
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SelectionGateway extends _Gateway implements SessionSelectionGateway {
  SessionSelection? createdSelection;
  final changes = <String>[];
  bool failSelection = false;
  bool busyAfterSelection = false;
  @override
  Future<Session> createSelectedSession(SessionSelection defaults) async {
    createdSelection = defaults;
    selection = defaults;
    return createSession();
  }

  @override
  Future<void> setSessionAgent(String sessionID, String agent) async {
    changes.add('agent:$agent');
    if (failSelection) throw StateError('ambiguous selection response');
    selection = (selection ?? const SessionSelection()).withAgent(agent);
    if (busyAfterSelection) status = 'busy';
  }

  @override
  Future<void> setSessionModel(
    String sessionID,
    ModelRef model,
    String variant,
  ) async {
    changes.add('model:${model.providerID}/${model.modelID}');
    if (failSelection) throw StateError('ambiguous selection response');
    selection = (selection ?? const SessionSelection()).withModel(
      model,
      variant,
    );
    if (busyAfterSelection) status = 'busy';
  }
}

void main() {
  final instant = DateTime.utc(2026, 10, 15, 8);
  late ServerProfile profile;
  late _Gateway gateway;
  late DateTime currentTime;
  late bool current;
  late bool phone;
  late int opens;
  late int releases;

  ScheduledPrompt schedule({
    String? sessionId = 'existing',
    String? fingerprint,
    String? agent,
    ModelRef? model,
  }) => ScheduledPrompt(
    id: 'schedule',
    profileId: profile.id,
    profileFingerprint: fingerprint ?? scheduledProfileFingerprint(profile),
    prompt: 'Summarize the project',
    projectPath: '/project',
    sessionId: sessionId,
    agent: agent,
    modelProviderId: model?.providerID,
    modelId: model?.modelID,
    recurrence: ScheduleRecurrence.once(instant),
    createdAt: instant,
    nextRunAt: instant,
  );

  ScheduledPromptRunner runner() => ScheduledPromptRunner(
    loadProfile: (_) async => profile,
    now: () => currentTime,
    delay: (duration) async {
      currentTime = currentTime.add(duration);
    },
    openConnection:
        ({
          required profile,
          required projectPath,
          workspace,
          required deadlineEpochMs,
        }) async {
          opens++;
          return ScheduledAgentConnection(
            gateway: gateway,
            startedPhoneServer: phone,
            release: () async {
              releases++;
            },
          );
        },
  );
  Future<ScheduledPromptRun> execute([ScheduledPrompt? value]) =>
      runner().execute(
        value ?? schedule(),
        deadlineEpochMs: instant
            .add(const Duration(seconds: 10))
            .millisecondsSinceEpoch,
        isCurrent: () async => current,
      );

  setUp(() {
    profile = ServerProfile(
      id: 'profile',
      name: 'Server',
      baseUrl: 'https://server.invalid',
      flavor: ServerFlavor.v2,
    );
    gateway = _Gateway();
    currentTime = instant;
    current = true;
    phone = false;
    opens = releases = 0;
  });

  for (final (refusal, code) in [
    (const ServerCertificateChangedException(), 'certificate_changed'),
    (const ServerCertificateValidityException(), 'certificate_invalid'),
  ]) {
    test(
      'a refused certificate is recorded as $code, not unreachable',
      () async {
        final api = Api2Gateway.connect(
          baseUrl: 'https://server.invalid',
          password: 'pw',
        );
        api.transport.dio.httpClientAdapter = _TrustRefusingAdapter(refusal);
        final result =
            await ScheduledPromptRunner(
              loadProfile: (_) async => profile,
              now: () => currentTime,
              openConnection:
                  ({
                    required profile,
                    required projectPath,
                    workspace,
                    required deadlineEpochMs,
                  }) async => ScheduledAgentConnection(gateway: api),
            ).execute(
              schedule(),
              deadlineEpochMs: instant
                  .add(const Duration(seconds: 10))
                  .millisecondsSinceEpoch,
              isCurrent: () async => true,
            );
        expect(result.status, ScheduledPromptRunStatus.failed);
        expect(result.errorCode, code);
      },
    );
  }

  test('route change refuses before creating a transport', () async {
    final result = await execute(schedule(fingerprint: 'old'));
    expect(result.errorCode, 'stale_target');
    expect(opens, 0);
    expect(gateway.sends, 0);
  });

  for (final existingTarget in [false, true]) {
    test(
      'persists ${existingTarget ? 'existing' : 'new'} conversation before prompt exactly once',
      () async {
        final receipts = <String>[];
        gateway.afterPrompt = () {
          expect(receipts, [existingTarget ? 'existing' : 'created']);
        };
        final result = await runner().execute(
          schedule(sessionId: existingTarget ? 'existing' : null),
          deadlineEpochMs: instant
              .add(const Duration(seconds: 10))
              .millisecondsSinceEpoch,
          isCurrent: () async => current,
          onSessionCreated: (id) async {
            receipts.add(id);
          },
        );
        expect(result.status, ScheduledPromptRunStatus.ran);
        expect(receipts, [existingTarget ? 'existing' : 'created']);
        expect(gateway.sends, 1);
      },
    );
  }

  test(
    'failure persisting created conversation prevents prompt dispatch',
    () async {
      final result = await runner().execute(
        schedule(sessionId: null),
        deadlineEpochMs: instant
            .add(const Duration(seconds: 10))
            .millisecondsSinceEpoch,
        isCurrent: () async => current,
        onSessionCreated: (_) async {
          throw StateError('storage failed');
        },
      );
      expect(result.status, ScheduledPromptRunStatus.failed);
      expect(result.errorCode, 'unavailable');
      expect(result.sessionId, 'created');
      expect(gateway.creates, 1);
      expect(gateway.sends, 0);
      expect(releases, 1);
    },
  );

  test(
    'persistent-selection servers create with captured agent and model',
    () async {
      final selected = _SelectionGateway();
      gateway = selected;
      final result = await execute(
        schedule(
          sessionId: null,
          agent: 'plan',
          model: ModelRef(providerID: 'provider', modelID: 'model'),
        ),
      );
      expect(result.status, ScheduledPromptRunStatus.ran);
      expect(selected.createdSelection?.agent, 'plan');
      expect(selected.createdSelection?.model?.providerID, 'provider');
      expect(selected.createdSelection?.model?.modelID, 'model');
      expect(selected.changes, isEmpty);
      expect(selected.creates, 1);
      expect(selected.sends, 1);
    },
  );

  test(
    'existing session changes captured agent without resetting uncaptured model',
    () async {
      final selected = _SelectionGateway()
        ..selection = SessionSelection(
          agent: 'build',
          model: ModelRef(providerID: 'keep', modelID: 'current'),
          variant: 'high',
        );
      gateway = selected;
      final result = await execute(schedule(agent: 'plan'));
      expect(result.status, ScheduledPromptRunStatus.ran);
      expect(selected.changes, ['agent:plan']);
      expect(selected.selection?.model?.modelID, 'current');
      expect(selected.selection?.variant, 'high');
    },
  );

  test(
    'matching captured selection preserves existing variant without writes',
    () async {
      final model = ModelRef(providerID: 'provider', modelID: 'model');
      final selected = _SelectionGateway()
        ..selection = SessionSelection(
          agent: 'plan',
          model: model,
          variant: 'high',
        );
      gateway = selected;
      expect(
        (await execute(schedule(agent: 'plan', model: model))).status,
        ScheduledPromptRunStatus.ran,
      );
      expect(selected.changes, isEmpty);
      expect(selected.selection?.variant, 'high');
    },
  );

  test(
    'captured model changes only the model of an idle existing session',
    () async {
      final selected = _SelectionGateway()
        ..selection = SessionSelection(
          agent: 'keep-agent',
          model: ModelRef(providerID: 'old', modelID: 'old-model'),
        );
      gateway = selected;
      final result = await execute(
        schedule(
          model: ModelRef(providerID: 'new', modelID: 'new-model'),
        ),
      );
      expect(result.status, ScheduledPromptRunStatus.ran);
      expect(selected.changes, ['model:new/new-model']);
      expect(selected.selection?.agent, 'keep-agent');
      expect(selected.sends, 1);
    },
  );

  test('uncertain selection is not retried or followed by a prompt', () async {
    final selected = _SelectionGateway()..failSelection = true;
    gateway = selected;
    final result = await execute(schedule(agent: 'plan'));
    expect(result.errorCode, 'uncertain_delivery');
    expect(selected.changes, ['agent:plan']);
    expect(selected.sends, 0);
  });

  test(
    'turn starting during selection skips prompt without undoing edits',
    () async {
      final selected = _SelectionGateway()..busyAfterSelection = true;
      gateway = selected;
      final result = await execute(schedule(agent: 'plan'));
      expect(result.status, ScheduledPromptRunStatus.skipped);
      expect(result.errorCode, 'busy');
      expect(selected.changes, ['agent:plan']);
      expect(selected.sends, 0);
    },
  );

  test('unqualified gateway cannot create or send scheduled work', () async {
    gateway.schedulingSupported = false;
    final result = await execute(schedule(sessionId: null));
    expect(result.errorCode, 'unsupported');
    expect(gateway.creates, 0);
    expect(gateway.sends, 0);
    expect(gateway.closed, isTrue);
  });

  test('cold socket status is hydrated before busy admission', () async {
    gateway.coldBusy = true;
    final result = await execute();
    expect(gateway.hydrated, isTrue);
    expect(result.status, ScheduledPromptRunStatus.skipped);
    expect(result.errorCode, 'busy');
    expect(gateway.sends, 0);
    expect(releases, 1);
  });

  test(
    'target deletion during read prevents mutation and closes connection',
    () async {
      gateway.afterSession = () {
        current = false;
      };
      final result = await execute();
      expect(result.errorCode, 'stale_target');
      expect(gateway.sends, 0);
      expect(gateway.closed, isTrue);
    },
  );

  test('existing conversation in another project is refused', () async {
    gateway.directoryValue = '/different';
    expect((await execute()).errorCode, 'wrong_project');
    expect(gateway.sends, 0);
  });

  test(
    'new conversation is created once and accepted remote run is recorded',
    () async {
      final result = await execute(schedule(sessionId: null));
      expect(result.status, ScheduledPromptRunStatus.ran);
      expect(result.sessionId, 'created');
      expect(gateway.creates, 1);
      expect(gateway.sends, 1);
      expect(releases, 1);
    },
  );

  test(
    'ambiguous delivery is never retried and does not expose response text',
    () async {
      gateway.failPrompt = true;
      final result = await execute();
      expect(result.status, ScheduledPromptRunStatus.failed);
      expect(result.errorCode, 'uncertain_delivery');
      expect(result.sessionId, 'existing');
      expect(gateway.sends, 1);
      expect(releases, 1);
    },
  );

  test(
    'phone lease waits for fresh output before closing owned runtime',
    () async {
      phone = true;
      gateway.completed = true;
      final result = await execute();
      expect(result.status, ScheduledPromptRunStatus.ran);
      expect(gateway.sends, 1);
      expect(releases, 1);
    },
  );

  test('old assistant output cannot qualify phone completion', () async {
    phone = true;
    final result = await execute();
    expect(result.status, ScheduledPromptRunStatus.failed);
    expect(result.errorCode, 'timeout');
    expect(gateway.sends, 1);
    expect(releases, 1);
  });

  test('phone permission wait is needs-you without approval', () async {
    phone = true;
    gateway.needsYou = true;
    final result = await execute();
    expect(result.status, ScheduledPromptRunStatus.failed);
    expect(result.errorCode, 'needs_you');
    expect(result.sessionId, 'existing');
    expect(releases, 1);
  });

  test(
    'profile rename preserves fingerprint but endpoint edits invalidate it',
    () {
      final fingerprint = scheduledProfileFingerprint(profile);
      profile.name = 'Renamed';
      expect(scheduledProfileFingerprint(profile), fingerprint);
      profile.baseUrl = 'https://changed.invalid';
      expect(scheduledProfileFingerprint(profile), isNot(fingerprint));
    },
  );

  test('cold connection rejects transient phone-agent routing', () async {
    final transient = ServerProfile(
      id: 'owner.agents',
      name: 'Phone agents',
      baseUrl: 'ws://127.0.0.1:4099',
      backend: ServerBackend.paseo,
      transientTransport: true,
    );
    await expectLater(
      ScheduledAgentConnection.open(
        profile: transient,
        projectPath: '/root/projects/test',
        deadlineEpochMs: instant.millisecondsSinceEpoch,
      ),
      throwsA(
        isA<ScheduledRunFailure>().having(
          (e) => e.reason,
          'reason',
          'unsupported',
        ),
      ),
    );
  });

  test(
    'cold connection refuses missing Codex credential before opening socket',
    () async {
      final codex = ServerProfile(
        id: 'codex',
        name: 'Codex',
        baseUrl: 'wss://codex.invalid',
        backend: ServerBackend.codex,
      );
      await expectLater(
        ScheduledAgentConnection.open(
          profile: codex,
          projectPath: '/project',
          deadlineEpochMs: instant.millisecondsSinceEpoch,
        ),
        throwsA(
          isA<ScheduledRunFailure>().having(
            (e) => e.reason,
            'reason',
            'auth_required',
          ),
        ),
      );
    },
  );
  test(
    'cold connection reaches a plain-HTTP server the person allowed',
    () async {
      // Q2 (2026-10-17): every scheduled run against an allowed
      // http://10.0.2.2:4097 failed as "could not be reached", because the
      // scheduled transport dropped the consent and refused every request.
      final profile = ServerProfile(
        id: 'lan',
        name: 'Desk',
        baseUrl: 'http://10.0.2.2:4097',
        password: 'pw',
      )..cleartextConfirmedOrigin = 'http://10.0.2.2:4097';
      expect(profile.cleartextUnconfirmed, isFalse);
      final connection = await ScheduledAgentConnection.open(
        profile: profile,
        projectPath: '/project',
        deadlineEpochMs: instant.millisecondsSinceEpoch,
      );
      addTearDown(connection.close);
      final adapter = _HealthAdapter();
      (connection.gateway as Api2Gateway).transport.dio.httpClientAdapter =
          adapter;

      final health = await connection.gateway.health();

      expect(health.healthy, isTrue);
      expect(
        adapter.requests.single.uri.toString(),
        startsWith('http://10.0.2.2:4097/api/health'),
      );
      expect(
        adapter.requests.single.headers['Authorization'],
        startsWith('Basic '),
      );
    },
  );

  test(
    'cold connection keeps the approved certificate of its server',
    () async {
      const pin =
          '0000000000000000000000000000000000000000000000000000000000000001';
      final profile =
          ServerProfile(
              id: 'pinned',
              name: 'Pinned',
              baseUrl: 'https://desk.example:4097',
              password: 'pw',
            )
            ..certificatePinOrigin = 'https://desk.example:4097'
            ..certificatePinSha256 = pin;
      final connection = await ScheduledAgentConnection.open(
        profile: profile,
        projectPath: '/project',
        deadlineEpochMs: instant.millisecondsSinceEpoch,
      );
      addTearDown(connection.close);
      expect(
        (connection.gateway as Api2Gateway).transport.certificatePinSha256,
        pin,
      );
    },
  );

  test('cold connection names a plain-HTTP server nobody allowed', () async {
    final profile = ServerProfile(
      id: 'lan',
      name: 'Desk',
      baseUrl: 'http://10.0.2.2:4097',
      password: 'pw',
    );
    await expectLater(
      ScheduledAgentConnection.open(
        profile: profile,
        projectPath: '/project',
        deadlineEpochMs: instant.millisecondsSinceEpoch,
      ),
      throwsA(
        isA<ScheduledRunFailure>().having(
          (e) => e.reason,
          'reason',
          'cleartext_unconfirmed',
        ),
      ),
    );
  });
}
