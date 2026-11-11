import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/scheduling/controller.dart';
import 'package:agentphone/scheduling/models.dart';
import 'package:agentphone/scheduling/platform.dart';
import 'package:agentphone/scheduling/recurrence.dart';
import 'package:agentphone/scheduling/store.dart';

class _Backend implements ScheduledPromptBackend {
  final values = <String, String>{};
  bool broken = false;
  @override
  Future<String?> read(String key) async {
    if (broken) throw StateError('Unavailable');
    return values[key];
  }

  @override
  Future<bool> compareAndSet(String key, String? expected, String value) async {
    if (values[key] != expected) return false;
    values[key] = value;
    return true;
  }
}

class _Platform extends ScheduledPromptsPlatform {
  bool supported = true;
  List<Map<String, dynamic>> receipts = [];
  List<Map<String, Object?>> entries = [];
  final acknowledgements = <String>[];
  DateTime? digestAt;
  int syncs = 0;
  @override
  Future<SchedulePlatformStatus> status() async => SchedulePlatformStatus(
    supported: supported,
    exactAllowed: false,
    notificationsAllowed: true,
  );
  @override
  Future<void> replaceProfile(
    String profileId,
    List<Map<String, Object?>> entries, {
    DateTime? digestAt,
  }) async {
    this.entries = entries;
    this.digestAt = digestAt;
    syncs++;
  }

  @override
  Future<List<Map<String, dynamic>>> readReceipts(String profileId) async =>
      List.of(receipts);
  @override
  Future<void> acknowledgeReceipts(String profileId, List<String> ids) async {
    acknowledgements.addAll(ids);
    receipts.removeWhere((row) => ids.contains(row['id']));
  }
}

final _due = DateTime.utc(2026, 10, 15, 8);
ScheduledPrompt _schedule({String profileId = 'phone', int revision = 1}) =>
    ScheduledPrompt(
      id: 'morning',
      profileId: profileId,
      profileFingerprint: 'route',
      prompt: 'Review tasks',
      projectPath: '/project',
      createdAt: _due,
      nextRunAt: _due,
      revision: revision,
      recurrence: ScheduleRecurrence.interval(hours: 2, anchor: _due),
    );
Map<String, dynamic> _receipt() => {
  'id': scheduledOccurrenceId(_schedule(), _due),
  'scheduleId': 'morning',
  'revision': 1,
  'scheduledAtMs': _due.millisecondsSinceEpoch,
  'finishedAtMs': _due.add(const Duration(minutes: 20)).millisecondsSinceEpoch,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'controller create edit pause resume delete updates native schedule',
    () async {
      final now = _due.subtract(const Duration(minutes: 1));
      final store = ScheduledPromptStore(backend: _Backend(), now: () => now);
      final platform = _Platform();
      final controller = ScheduledPromptsController(
        profileId: 'phone',
        store: store,
        platform: platform,
        now: () => now,
      );
      addTearDown(controller.dispose);
      await controller.load();
      expect(controller.errorCode, isNull);
      expect(controller.platformStatus.exactAllowed, isFalse);
      await controller.save(_schedule());
      expect(controller.schedules.single.prompt, 'Review tasks');
      expect(platform.entries.single['dueAtMs'], _due.millisecondsSinceEpoch);
      await controller.save(
        _schedule(revision: 2).copyWith(prompt: 'Review changes'),
      );
      expect(controller.schedules.single.prompt, 'Review changes');
      await controller.setEnabled('morning', false);
      expect(platform.entries, isEmpty);
      await controller.setEnabled('morning', true);
      expect(platform.entries, hasLength(1));
      await controller.setDigest(const ScheduledPromptDigest(enabled: true));
      expect(controller.digest.enabled, isTrue);
      expect(platform.digestAt, isNotNull);
      await controller.delete('morning');
      expect(controller.schedules, isEmpty);
      expect(platform.entries, isEmpty);
    },
  );

  test(
    'unsupported platform and cross-profile save reject admission',
    () async {
      final platform = _Platform()..supported = false;
      final controller = ScheduledPromptsController(
        profileId: 'phone',
        store: ScheduledPromptStore(backend: _Backend()),
        platform: platform,
      );
      addTearDown(controller.dispose);
      await controller.load();
      expect(controller.errorCode, 'unsupported');
      expect(controller.loading, isFalse);
      await expectLater(
        controller.save(_schedule()),
        throwsA(isA<ScheduledPromptStoreException>()),
      );
      expect(controller.errorCode, 'unsupported');
      platform.supported = true;
      await controller.load();
      await expectLater(
        controller.save(_schedule(profileId: 'other')),
        throwsA(isA<ScheduledPromptStoreException>()),
      );
      expect(controller.errorCode, 'unsupported');
      expect(controller.schedules, isEmpty);
    },
  );

  test('mutation errors retain actionable code and notify listeners', () async {
    final backend = _Backend();
    final controller = ScheduledPromptsController(
      profileId: 'phone',
      store: ScheduledPromptStore(backend: backend),
      platform: _Platform(),
    );
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() => notifications++);
    await controller.load();
    await controller.save(_schedule());
    final before = notifications;
    await expectLater(
      controller.save(_schedule()),
      throwsA(isA<ScheduledPromptStoreException>()),
    );
    expect(controller.errorCode, 'stale_schedule');
    expect(notifications, greaterThan(before));
    backend.broken = true;
    await controller.load();
    expect(controller.errorCode, 'storage_unavailable');
    expect(controller.loading, isFalse);
  });

  test(
    'native timeout receipt creates failed history and advances once',
    () async {
      final store = ScheduledPromptStore(backend: _Backend());
      await store.save(_schedule());
      final platform = _Platform()..receipts = [_receipt()];
      final controller = ScheduledPromptsController(
        profileId: 'phone',
        store: store,
        platform: platform,
        now: () => _due.add(const Duration(minutes: 20)),
      );
      addTearDown(controller.dispose);
      await controller.load();
      expect(controller.errorCode, isNull);
      expect(controller.runs.single.status, ScheduledPromptRunStatus.failed);
      expect(controller.runs.single.errorCode, 'interrupted');
      expect(controller.runs.single.late, isTrue);
      expect(
        controller.schedules.single.nextRunAt,
        _due.add(const Duration(hours: 2)),
      );
      expect(platform.acknowledgements, [_receipt()['id']]);
      await controller.load();
      expect(controller.runs, hasLength(1));
    },
  );

  test(
    'native receipt recovers running history preserving original start',
    () async {
      final store = ScheduledPromptStore(backend: _Backend());
      await store.save(_schedule());
      await store.recordRun(
        'phone',
        ScheduledPromptRun(
          id: scheduledOccurrenceId(_schedule(), _due),
          scheduleId: 'morning',
          scheduledAt: _due,
          startedAt: _due,
          status: ScheduledPromptRunStatus.running,
        ),
      );
      final platform = _Platform()..receipts = [_receipt()];
      final controller = ScheduledPromptsController(
        profileId: 'phone',
        store: store,
        platform: platform,
        now: () => _due.add(const Duration(minutes: 20)),
      );
      addTearDown(controller.dispose);
      await controller.load();
      expect(controller.errorCode, isNull);
      expect(controller.runs.single.status, ScheduledPromptRunStatus.failed);
      expect(controller.runs.single.startedAt, _due);
      expect(controller.runs.single.errorCode, 'interrupted');
      expect(
        controller.schedules.single.nextRunAt,
        _due.add(const Duration(hours: 2)),
      );
    },
  );

  test(
    'old native receipt cannot advance edited schedule or recreate deleted one',
    () async {
      final store = ScheduledPromptStore(backend: _Backend());
      await store.save(_schedule());
      await store.save(_schedule(revision: 2));
      final platform = _Platform()..receipts = [_receipt()];
      final controller = ScheduledPromptsController(
        profileId: 'phone',
        store: store,
        platform: platform,
        now: () => _due.add(const Duration(minutes: 20)),
      );
      addTearDown(controller.dispose);
      await controller.load();
      expect(controller.schedules.single.revision, 2);
      expect(controller.schedules.single.nextRunAt, _due);
      await store.delete('phone', 'morning');
      platform.receipts = [_receipt()];
      await controller.load();
      expect(controller.schedules, isEmpty);
      expect(controller.runs, isEmpty);
      expect(platform.receipts, isEmpty);
    },
  );

  test('digest calendar selects next local morning including next day', () {
    const digest = ScheduledPromptDigest(enabled: true, hour: 8);
    final before = DateTime(2026, 10, 15, 7, 59);
    expect(nextDigestAt(digest, before), DateTime(2026, 10, 15, 8).toUtc());
    expect(
      nextDigestAt(digest, DateTime(2026, 10, 15, 8)),
      DateTime(2026, 10, 16, 8).toUtc(),
    );
  });
}
