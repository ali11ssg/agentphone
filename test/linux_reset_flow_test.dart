// Reset Linux as one act (lib/builtin/linux_manager/linux_reset_flow.dart):
// marked before anything is erased, so a reset the app did not finish is
// finished on the next start, never left as an erased Linux with no setup.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/builtin/builtin_linux.dart';
import 'package:agentphone/builtin/linux_manager/linux_reset_flow.dart';
import 'package:agentphone/builtin/reply_watch.dart'
    show replySpeedPreferenceKey;
import 'package:agentphone/builtin/setup/setup_contract.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Linux extends BuiltinLinux {
  _Linux(this.prefs);
  final SharedPreferences prefs;
  bool installed = true;
  var uninstalls = 0;
  bool? markedWhenErased;

  @override
  Future<BuiltinLinuxStatus> status() async => BuiltinLinuxStatus(
    installed: installed,
    phase: installed ? BuiltinLinuxPhase.ready : BuiltinLinuxPhase.idle,
  );

  @override
  Future<void> uninstall() async {
    uninstalls++;
    markedWhenErased = LinuxResetFlow.pending(prefs);
    installed = false;
  }
}

class _Engine implements SetupEngine {
  final runs = <Set<String>>[];
  SetupState next = SetupState.running;
  final _progress = ValueNotifier<SetupProgress>(SetupProgress.idle);

  @override
  List<SetupComponent> get registry => const [];

  @override
  ValueListenable<SetupProgress> get progress => _progress;

  @override
  Future<void> run(
    Set<String> ids, {
    Map<String, Map<String, String>> params = const {},
  }) async {
    runs.add(ids);
    _progress.value = SetupProgress(
      state: next,
      components: const [],
      overall: 0,
    );
  }

  @override
  Future<void> restore({SetupReadScope? scope}) async {}

  @override
  Future<void> cancel() async {}

  @override
  Future<Set<String>> installedOptional() async => {};
}

void main() {
  late SharedPreferences prefs;
  late _Linux linux;
  late _Engine engine;

  LinuxResetFlow flow() => LinuxResetFlow(
    linux: linux,
    engine: engine,
    prefs: prefs,
    selection: const {'linux', 'opencode'},
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    linux = _Linux(prefs);
    engine = _Engine();
  });

  test('the marker is saved before anything is erased, and goes once '
      'setup runs', () async {
    final outcome = await flow().run();
    expect(outcome.result, LinuxResetResult.reinstalling);
    expect(linux.markedWhenErased, isTrue);
    expect(engine.runs, [
      {'linux', 'opencode'},
    ]);
    expect(LinuxResetFlow.pending(prefs), isFalse);
  });

  test('the old Reply speed reading goes with the erased Linux', () async {
    await prefs.setString(replySpeedPreferenceKey, '{"total":1}');
    await flow().run();
    expect(prefs.getString(replySpeedPreferenceKey), isNull);
  });

  test(
    'a setup that could not start keeps the marker for the next start',
    () async {
      engine.next = SetupState.failed;
      await flow().run();
      expect(LinuxResetFlow.pending(prefs), isTrue);
    },
  );

  test('killed while erasing: the next start erases and sets up', () async {
    await prefs.setString(LinuxResetFlow.markerKey, 'erasing 2026-10-16');
    expect(await flow().resumeIfPending(), isTrue);
    expect(linux.uninstalls, 1);
    expect(engine.runs, hasLength(1));
    expect(LinuxResetFlow.pending(prefs), isFalse);
  });

  test('killed after erasing: the next start only sets up', () async {
    linux.installed = false;
    await prefs.setString(LinuxResetFlow.markerKey, 'installing 2026-10-16');
    expect(await flow().resumeIfPending(), isTrue);
    expect(linux.uninstalls, 0);
    expect(engine.runs, hasLength(1));
    expect(LinuxResetFlow.pending(prefs), isFalse);
  });

  test('a Linux installed again since then ends the reset quietly', () async {
    await prefs.setString(LinuxResetFlow.markerKey, 'installing 2026-10-16');
    expect(await flow().resumeIfPending(), isFalse);
    expect(linux.uninstalls, 0);
    expect(engine.runs, isEmpty);
    expect(LinuxResetFlow.pending(prefs), isFalse);
  });

  test('no marker, nothing to do', () async {
    expect(await flow().resumeIfPending(), isFalse);
    expect(linux.uninstalls, 0);
    expect(engine.runs, isEmpty);
  });
}
