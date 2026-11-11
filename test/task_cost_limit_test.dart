// The cost limit for one task: a run that passes it is stopped by the phone.
import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/state/task_cost_limit.dart';

void main() {
  group('the limit decides', () {
    test('no limit stops nothing', () {
      expect(TaskCostLimit.exceeded(null, 100), isFalse);
      expect(TaskCostLimit.exceeded(0, 100), isFalse);
    });

    test('a run under the limit keeps going', () {
      expect(TaskCostLimit.exceeded(2.5, 1.0), isFalse);
      expect(TaskCostLimit.exceeded(2.5, 2.49), isFalse);
    });

    test('a run at or over the limit stops', () {
      expect(TaskCostLimit.exceeded(2.5, 2.5), isTrue);
      expect(TaskCostLimit.exceeded(2.5, 9.0), isTrue);
    });

    test('an unknown cost stops nothing', () {
      expect(TaskCostLimit.exceeded(2.5, null), isFalse);
    });
  });

  group('the key', () {
    test('is per profile', () {
      expect(TaskCostLimit.keyFor('one'), isNot(TaskCostLimit.keyFor('two')));
    });
  });
}
