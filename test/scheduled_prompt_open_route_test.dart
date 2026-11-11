import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/scheduling/models.dart';
import 'package:agentphone/scheduling/open_route.dart';

final _at = DateTime.utc(2026, 10, 17, 6, 15);

ScheduledPrompt _schedule(String id) => ScheduledPrompt(
  id: id,
  profileId: 'desk',
  profileFingerprint: 'route',
  prompt: 'Reply with one word',
  projectPath: '/project',
  sessionId: 'conversation',
  recurrence: ScheduleRecurrence.once(_at),
  createdAt: _at,
  nextRunAt: _at,
);

ScheduledPromptRun _run(
  String scheduleId,
  ScheduledPromptRunStatus status, {
  String? sessionId,
  String? error,
}) => ScheduledPromptRun(
  id: '$scheduleId:1:${_at.millisecondsSinceEpoch}',
  scheduleId: scheduleId,
  scheduledAt: _at,
  startedAt: _at,
  finishedAt: _at,
  status: status,
  sessionId: sessionId,
  errorCode: error,
);

void main() {
  final schedules = [_schedule('morning'), _schedule('evening')];

  ScheduledOpenRoute? resolve(
    Map<String, dynamic> payload, {
    List<ScheduledPromptRun> history = const [],
    String? fingerprint = 'route',
  }) => resolveScheduledOpen(
    payload: payload,
    profileFingerprint: fingerprint,
    schedules: schedules,
    history: history,
  );

  // The payload is what the native notification carries:
  // ScheduledPromptNotifications puts profile, schedule and session extras.
  for (final status in [
    ScheduledPromptRunStatus.ran,
    ScheduledPromptRunStatus.failed,
    ScheduledPromptRunStatus.skipped,
  ]) {
    test('a ${status.name} run that reached its conversation opens it', () {
      final route = resolve(
        {
          'profileId': 'desk',
          'scheduleId': 'evening',
          'sessionId': 'conversation',
        },
        history: [_run('evening', status, sessionId: 'conversation')],
      );
      expect(route, isA<ScheduledOpenConversation>());
      route as ScheduledOpenConversation;
      expect(route.schedule.id, 'evening');
      expect(route.sessionId, 'conversation');
    });
  }

  test('a failed run without a conversation opens the history', () {
    final route = resolve(
      {'profileId': 'desk', 'scheduleId': 'evening', 'sessionId': ''},
      history: [
        _run('evening', ScheduledPromptRunStatus.failed, error: 'unavailable'),
      ],
    );
    expect(route, isA<ScheduledOpenHistory>());
    expect(route!.schedule.id, 'evening');
  });

  test('a conversation this schedule never used opens the history', () {
    final route = resolve(
      {'profileId': 'desk', 'scheduleId': 'evening', 'sessionId': 'other'},
      history: [
        _run('morning', ScheduledPromptRunStatus.ran, sessionId: 'other'),
      ],
    );
    expect(route, isA<ScheduledOpenHistory>());
  });

  test('the morning summary opens the history', () {
    // Native sends an empty schedule ID for the summary.
    expect(
      resolve({'profileId': 'desk', 'scheduleId': '', 'sessionId': ''}),
      isA<ScheduledOpenHistory>(),
    );
    expect(
      resolve({'profileId': 'desk', 'scheduleId': '__digest'}),
      isA<ScheduledOpenHistory>(),
    );
  });

  test('a deleted schedule or a changed server opens nothing', () {
    expect(resolve({'profileId': 'desk', 'scheduleId': 'gone'}), isNull);
    expect(
      resolve({
        'profileId': 'desk',
        'scheduleId': 'evening',
      }, fingerprint: 'moved'),
      isNull,
    );
    expect(
      resolve({
        'profileId': 'desk',
        'scheduleId': 'evening',
      }, fingerprint: null),
      isNull,
    );
    expect(resolve({'profileId': 'other', 'scheduleId': 'evening'}), isNull);
  });
}
