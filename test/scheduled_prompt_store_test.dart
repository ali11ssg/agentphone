import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/scheduling/models.dart';
import 'package:agentphone/scheduling/store.dart';

class _Backend implements ScheduledPromptBackend {
  final values = <String, String>{};
  bool refuse = false;
  bool deleted = false;
  int conflicts = 0;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<bool> compareAndSet(String key, String? expected, String value) async {
    if (deleted) throw StateError('Profile removed');
    if (refuse) return false;
    if (conflicts > 0) {
      conflicts--;
      return false;
    }
    if (values[key] != expected) return false;
    values[key] = value;
    return true;
  }
}

ScheduledPrompt _schedule(
  String id, {
  String profile = 'phone',
  int revision = 1,
}) => ScheduledPrompt(
  id: id,
  profileId: profile,
  profileFingerprint: 'route_digest',
  prompt: 'Review tasks',
  projectPath: '/project',
  revision: revision,
  recurrence: ScheduleRecurrence.once(DateTime.utc(2026, 10, 15, 8)),
  createdAt: DateTime.utc(2026, 10, 15),
  nextRunAt: DateTime.utc(2026, 10, 15, 8),
);
ScheduledPromptRun _run({
  ScheduledPromptRunStatus status = ScheduledPromptRunStatus.running,
}) => ScheduledPromptRun(
  id: 'morning:1:123',
  scheduleId: 'morning',
  scheduledAt: DateTime.utc(2026, 10, 15, 8),
  startedAt: DateTime.utc(2026, 10, 15, 8),
  status: status,
);
Matcher _code(String code) => throwsA(
  isA<ScheduledPromptStoreException>().having(
    (error) => error.code,
    'code',
    code,
  ),
);

void main() {
  test(
    'restart preserves schedules, paused state, history and opt-in digest',
    () async {
      final backend = _Backend();
      final store = ScheduledPromptStore(backend: backend);
      expect((await store.digest('phone')).enabled, isFalse);
      await store.save(_schedule('morning'));
      await store.setEnabled('phone', 'morning', false);
      await store.recordRun('phone', _run());
      await store.recordRun(
        'phone',
        _run(status: ScheduledPromptRunStatus.ran),
      );
      await store.setDigest(
        'phone',
        const ScheduledPromptDigest(enabled: true, hour: 7),
      );
      final reopened = ScheduledPromptStore(backend: backend);
      expect((await reopened.load('phone')).single.enabled, isFalse);
      expect(
        (await reopened.history('phone')).single.status,
        ScheduledPromptRunStatus.ran,
      );
      expect((await reopened.digest('phone')).hour, 7);
      expect((await reopened.digest('phone')).enabled, isTrue);
      expect((await reopened.load('other')), isEmpty);
    },
  );

  test(
    'local run timestamps survive JSON before dispatch and completion',
    () async {
      final backend = _Backend();
      final store = ScheduledPromptStore(backend: backend);
      await store.save(_schedule('morning'));
      final due = DateTime.utc(2026, 10, 15, 8).toLocal();
      final admitted = DateTime.utc(2026, 10, 15, 8, 0, 0, 123, 456).toLocal();
      expect(admitted.isUtc, isFalse);
      ScheduledPromptRun run({
        ScheduledPromptRunStatus status = ScheduledPromptRunStatus.running,
        String? sessionId,
        DateTime? startedAt,
      }) => ScheduledPromptRun(
        id: 'morning:1:123',
        scheduleId: 'morning',
        scheduledAt: due,
        startedAt: startedAt ?? admitted,
        status: status,
        sessionId: sessionId,
        finishedAt: status == ScheduledPromptRunStatus.ran
            ? admitted.add(const Duration(seconds: 1))
            : null,
      );
      await store.recordRun('phone', run());
      final reopened = ScheduledPromptStore(backend: backend);
      final persisted = (await reopened.history('phone')).single;
      expect(persisted.startedAt.isUtc, isTrue);
      expect(
        persisted.startedAt.microsecondsSinceEpoch,
        admitted.microsecondsSinceEpoch,
      );
      // The pre-send session checkpoint uses the original local admission time.
      await reopened.recordRun('phone', run(sessionId: 'session_1'));
      await reopened.recordRun(
        'phone',
        run(status: ScheduledPromptRunStatus.ran, sessionId: 'session_1'),
      );
      final completed = (await reopened.history('phone')).single;
      expect(completed.status, ScheduledPromptRunStatus.ran);
      expect(completed.sessionId, 'session_1');
      // An identical terminal receipt is idempotent across local/UTC forms.
      await reopened.recordRun(
        'phone',
        run(status: ScheduledPromptRunStatus.ran, sessionId: 'session_1'),
      );
      // Same instant comparisons do not permit different microseconds or changed terminal data.
      await expectLater(
        reopened.recordRun(
          'phone',
          run(
            status: ScheduledPromptRunStatus.ran,
            sessionId: 'session_1',
            startedAt: admitted.add(const Duration(microseconds: 1)),
          ),
        ),
        _code('invalid_run_transition'),
      );
      await expectLater(
        reopened.recordRun(
          'phone',
          run(status: ScheduledPromptRunStatus.ran, sessionId: 'other_session'),
        ),
        _code('invalid_run_transition'),
      );
      await expectLater(
        reopened.recordRun('phone', run(sessionId: 'session_1')),
        _code('invalid_run_transition'),
      );
    },
  );

  test(
    'advance compares local scheduled time by instant after JSON reload',
    () async {
      final store = ScheduledPromptStore(backend: _Backend());
      final localDue = DateTime.utc(2026, 10, 15, 8, 0, 0, 123, 456).toLocal();
      final schedule = _schedule('morning').copyWith(nextRunAt: localDue);
      await store.save(schedule);
      final wrongInstant = schedule.copyWith(
        nextRunAt: localDue.add(const Duration(microseconds: 1)),
      );
      expect(await store.advanceOccurrence(wrongInstant, null), isFalse);
      expect(await store.advanceOccurrence(schedule, null), isTrue);
      final advanced = (await store.load('phone')).single;
      expect(advanced.nextRunAt, isNull);
      expect(advanced.enabled, isFalse);
    },
  );

  test('concurrent CAS writers preserve unrelated schedule edits', () async {
    final backend = _Backend();
    final first = ScheduledPromptStore(backend: backend);
    final second = ScheduledPromptStore(backend: backend);
    await Future.wait([
      first.save(_schedule('a')),
      second.save(_schedule('b')),
    ]);
    expect((await first.load('phone')).map((row) => row.id).toSet(), {
      'a',
      'b',
    });
    backend.conflicts = 2;
    await second.save(_schedule('c'));
    expect((await first.load('phone')).length, 3);
  });

  test(
    'refused persistence and deleted-profile fence never report success',
    () async {
      final backend = _Backend()..refuse = true;
      final store = ScheduledPromptStore(backend: backend);
      await expectLater(
        store.save(_schedule('morning')),
        _code('storage_busy'),
      );
      expect(backend.values, isEmpty);
      backend.refuse = false;
      backend.deleted = true;
      await expectLater(
        store.save(_schedule('morning')),
        _code('storage_unavailable'),
      );
      expect(backend.values, isEmpty);
    },
  );

  test(
    'corrupt or foreign-profile state is not silently overwritten',
    () async {
      final backend = _Backend();
      final store = ScheduledPromptStore(backend: backend);
      final key = ScheduledPromptStore.keyFor('phone');
      backend.values[key] = '{bad json';
      await expectLater(store.load('phone'), _code('storage_corrupt'));
      await expectLater(
        store.save(_schedule('morning')),
        _code('storage_corrupt'),
      );
      expect(backend.values[key], '{bad json');
      backend.values.clear();
      await store.save(_schedule('morning', profile: 'other'));
      backend.values[key] =
          backend.values[ScheduledPromptStore.keyFor('other')]!;
      await expectLater(store.load('phone'), _code('storage_corrupt'));
    },
  );

  test(
    'delete removes visible history and profile-scoped envelope is sweepable',
    () async {
      final backend = _Backend();
      final store = ScheduledPromptStore(backend: backend);
      await store.save(_schedule('morning'));
      await store.recordRun('phone', _run());
      await store.delete('phone', 'morning');
      expect(await store.load('phone'), isEmpty);
      expect(await store.history('phone'), isEmpty);
      expect(backend.values.keys.single, 'oc.scheduledPrompts.phone');
      await expectLater(
        store.recordRun('phone', _run()),
        _code('schedule_missing'),
      );
    },
  );

  test('stale schedule edits and terminal run rewrites are rejected', () async {
    final store = ScheduledPromptStore(backend: _Backend());
    await store.save(_schedule('morning', revision: 2));
    await expectLater(
      store.save(_schedule('morning')),
      _code('stale_schedule'),
    );
    await store.recordRun('phone', _run());
    await store.recordRun('phone', _run(status: ScheduledPromptRunStatus.ran));
    await expectLater(
      store.recordRun('phone', _run()),
      _code('invalid_run_transition'),
    );
    await store.recordRun('phone', _run(status: ScheduledPromptRunStatus.ran));
    expect((await store.history('phone')).length, 1);
  });

  test(
    'schema drift and duplicate ids fail closed; lists are immutable',
    () async {
      final backend = _Backend();
      final store = ScheduledPromptStore(backend: backend);
      await store.save(_schedule('morning'));
      final schedules = await store.load('phone');
      expect(() => schedules.clear(), throwsUnsupportedError);
      final key = ScheduledPromptStore.keyFor('phone');
      final envelope = jsonDecode(backend.values[key]!) as Map<String, dynamic>;
      envelope['schemaVersion'] = 999;
      backend.values[key] = jsonEncode(envelope);
      await expectLater(store.load('phone'), _code('storage_corrupt'));
      envelope['schemaVersion'] = 1;
      envelope['schedules'] = [
        _schedule('morning').toJson(),
        _schedule('morning').toJson(),
      ];
      backend.values[key] = jsonEncode(envelope);
      await expectLater(store.load('phone'), _code('storage_corrupt'));
    },
  );
  test(
    'advance cannot resurrect deleted or overwrite edited schedules',
    () async {
      final store = ScheduledPromptStore(backend: _Backend());
      final original = _schedule('morning');
      await store.save(original);
      await store.save(
        original.copyWith(prompt: 'Updated prompt', revision: 2),
      );
      expect(await store.advanceOccurrence(original, null), isFalse);
      expect((await store.load('phone')).single.prompt, 'Updated prompt');
      final edited = (await store.load('phone')).single;
      expect(await store.advanceOccurrence(edited, null), isTrue);
      expect((await store.load('phone')).single.enabled, isFalse);
      expect((await store.load('phone')).single.nextRunAt, isNull);
      await store.delete('phone', 'morning');
      expect(await store.advanceOccurrence(original, null), isFalse);
      expect(await store.load('phone'), isEmpty);
    },
  );

  test(
    'resuming skips paused occurrences and past once requires editing',
    () async {
      final store = ScheduledPromptStore(
        backend: _Backend(),
        now: () => DateTime.utc(2026, 10, 20, 9),
      );
      final recurring = _schedule('morning').copyWith(
        recurrence: ScheduleRecurrence.interval(
          hours: 2,
          anchor: DateTime.utc(2026, 10, 15, 8),
        ),
      );
      await store.save(recurring);
      await store.setEnabled('phone', 'morning', false);
      expect((await store.load('phone')).single.nextRunAt, isNull);
      await store.setEnabled('phone', 'morning', true);
      expect(
        (await store.load('phone')).single.nextRunAt,
        DateTime.utc(2026, 10, 20, 10),
      );
      await store.save(_schedule('once').copyWith(enabled: false));
      await expectLater(
        store.setEnabled('phone', 'once', true),
        _code('schedule_expired'),
      );
      expect(
        (await store.load(
          'phone',
        )).firstWhere((row) => row.id == 'once').enabled,
        isFalse,
      );
    },
  );

  test('same revision edits cannot overwrite a concurrent save', () async {
    final store = ScheduledPromptStore(backend: _Backend());
    await store.save(_schedule('morning'));
    await expectLater(
      store.save(_schedule('morning')),
      _code('stale_schedule'),
    );
    await store.save(_schedule('morning', revision: 2));
    await expectLater(
      store.save(_schedule('morning', revision: 2)),
      _code('stale_schedule'),
    );
  });

  test(
    'digest claims are once per cutoff and respect concurrent disabling',
    () async {
      final store = ScheduledPromptStore(backend: _Backend());
      const enabled = ScheduledPromptDigest(enabled: true);
      final cutoff = DateTime.utc(2026, 10, 15, 8);
      await store.setDigest('phone', enabled);
      expect(await store.claimDigest('phone', enabled, cutoff), isTrue);
      expect(await store.claimDigest('phone', enabled, cutoff), isFalse);
      final claimed = await store.digest('phone');
      expect(await store.claimDigest('phone', claimed, cutoff), isFalse);
      await store.setDigest('phone', const ScheduledPromptDigest());
      expect(
        await store.claimDigest(
          'phone',
          claimed,
          cutoff.add(const Duration(days: 1)),
        ),
        isFalse,
      );
      expect((await store.digest('phone')).enabled, isFalse);
    },
  );
}
