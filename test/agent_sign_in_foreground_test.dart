import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/domain/agent_sign_in_foreground.dart';

class _Lease implements AgentSignInForegroundLease {
  _Lease(this.log, [this.refusal]);
  final List<String> log;
  final AgentSignInForegroundException? refusal;
  final events = StreamController<AgentSignInForegroundException>.broadcast(
    sync: true,
  );
  @override
  bool active = true;
  @override
  Future<void> get ready =>
      refusal == null ? Future<void>.value() : Future<void>.error(refusal!);
  @override
  Stream<AgentSignInForegroundException> get lost => events.stream;
  @override
  Future<void> release() async {
    if (!active) return;
    active = false;
    log.add('release');
    await events.close();
  }
}

class _Port implements AgentSignInForegroundPort {
  _Port([this.refusal]);
  final AgentSignInForegroundException? refusal;
  final log = <String>[];
  final leases = <_Lease>[];
  @override
  AgentSignInForegroundLease reserveAgentSignInForeground() {
    log.add('reserve');
    return _add();
  }

  _Lease _add() {
    final lease = _Lease(log, refusal);
    leases.add(lease);
    return lease;
  }
}

void main() {
  test('a refused service keeps its code through the owner binding', () async {
    final port = _Port(
      const AgentSignInForegroundException(
        AgentSignInForegroundFailure.unavailable,
        code: 'service-not-started',
      ),
    );
    final binding = AgentSignInForegroundRegistry.bind('coded-refusal', port);
    final lease = binding.reserve();
    var losses = 0;
    final subscription = lease.lost.listen((_) => losses++);
    await expectLater(
      lease.ready,
      throwsA(
        isA<AgentSignInForegroundException>().having(
          (e) => e.code,
          'code',
          'service-not-started',
        ),
      ),
    );
    // A refusal is not a loss: only ready reports it.
    expect(losses, 0);
    await subscription.cancel();
    await AgentSignInForegroundRegistry.unbind(binding);
  });

  test('a running service that stops says what stopped it', () async {
    final port = _Port();
    final binding = AgentSignInForegroundRegistry.bind('coded-loss', port);
    final lease = binding.reserve();
    await lease.ready;
    final losses = <AgentSignInForegroundException>[];
    final subscription = lease.lost.listen(losses.add);
    port.leases.single.events.add(
      const AgentSignInForegroundException(
        AgentSignInForegroundFailure.paused,
        code: 'android-time-limit',
      ),
    );
    expect(losses.single.code, 'android-time-limit');
    expect(losses.single.reason, AgentSignInForegroundFailure.paused);
    await subscription.cancel();
    await AgentSignInForegroundRegistry.unbind(binding);
  });

  test('successive replacement cannot skip the oldest pending drain', () async {
    final first = AgentSignInForegroundRegistry.bind(
      'foreground-chain',
      _Port(),
    );
    final drain = Completer<void>();
    first.addCleanup(() => drain.future);
    AgentSignInForegroundRegistry.bind('foreground-chain', _Port());
    final lastPort = _Port();
    final last = AgentSignInForegroundRegistry.bind(
      'foreground-chain',
      lastPort,
    );
    final lease = last.reserve();
    await pumpEventQueue();
    final beforeDrain = List<String>.of(lastPort.log);
    drain.complete();
    await lease.ready;
    await AgentSignInForegroundRegistry.unbind(last);
    expect(beforeDrain, isEmpty);
  });
  test(
    'replacement waits for old terminal drain and foreground release',
    () async {
      final oldPort = _Port();
      final old = AgentSignInForegroundRegistry.bind(
        'foreground-replacement',
        oldPort,
      );
      final oldLease = old.reserve();
      await oldLease.ready;
      final drain = Completer<void>();
      old.addCleanup(() async {
        oldPort.log.add('drain');
        await drain.future;
      });
      final nextPort = _Port();
      final next = AgentSignInForegroundRegistry.bind(
        'foreground-replacement',
        nextPort,
      );
      final nextLease = next.reserve();
      await pumpEventQueue();
      expect(oldPort.log, ['reserve', 'drain']);
      expect(nextPort.log, isEmpty);
      drain.complete();
      await nextLease.ready;
      expect(oldPort.log, ['reserve', 'drain', 'release']);
      expect(nextLease.active, true);
      await AgentSignInForegroundRegistry.unbind(next);
    },
  );

  test('old unbind cannot clear a replacement binding', () async {
    final old = AgentSignInForegroundRegistry.bind('foreground-stale', _Port());
    final next = AgentSignInForegroundRegistry.bind(
      'foreground-stale',
      _Port(),
    );
    await AgentSignInForegroundRegistry.unbind(old);
    expect(
      AgentSignInForegroundRegistry.bindingFor('foreground-stale'),
      same(next),
    );
    expect(next.current, true);
    await AgentSignInForegroundRegistry.unbind(next);
  });

  test(
    'cancelling a reservation before the drain gate never starts a service',
    () async {
      final drain = Completer<void>();
      final old = AgentSignInForegroundRegistry.bind(
        'foreground-cancel',
        _Port(),
      );
      old.addCleanup(() => drain.future);
      final port = _Port();
      final next = AgentSignInForegroundRegistry.bind(
        'foreground-cancel',
        port,
      );
      final lease = next.reserve();
      final failed = expectLater(
        lease.ready,
        throwsA(isA<AgentSignInForegroundException>()),
      );
      await lease.release();
      await failed;
      drain.complete();
      await pumpEventQueue();
      expect(port.log, isEmpty);
      await AgentSignInForegroundRegistry.unbind(next);
    },
  );

  test('failed cleanup blocks admission and remains retryable', () async {
    var fail = true;
    final old = AgentSignInForegroundRegistry.bind('foreground-retry', _Port());
    old.addCleanup(() async {
      if (fail) throw StateError('private native text');
    });
    await expectLater(
      AgentSignInForegroundRegistry.unbind(old),
      throwsA(isA<AgentSignInForegroundException>()),
    );
    fail = false;
    await AgentSignInForegroundRegistry.unbind(old);
    final next = AgentSignInForegroundRegistry.bind(
      'foreground-retry',
      _Port(),
    );
    final lease = next.reserve();
    await lease.ready;
    expect(lease.active, true);
    await AgentSignInForegroundRegistry.unbind(next);
  });
}
