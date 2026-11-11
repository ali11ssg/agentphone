// AI Team starts fast on a phone (docs/qa/team-hot-2026-09-26): an agent's
// cold OpenCode start is given time instead of being cut off and started
// again, a team made by an earlier version gets that on its next start,
// the agents use OpenCode 2 without fetching models again or changing project
// package files, and the supervisor's own start lines are read back.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/builtin/builtin_linux.dart';
import 'package:agentphone/builtin/setup/aiteam_scripts.dart';
import 'package:agentphone/builtin/team/builtin_team.dart';
import 'package:agentphone/platform/platform_capabilities.dart';

/// The owner's phone's store before this change: tuned by the previous
/// version (it has the agents' `exec opencode`), with no start times.
const _previousCity = '''
[workspace]
provider = "opencode"
install_agent_hooks = ["opencode"]

[providers]
[providers.opencode]
base = "builtin:opencode"
acp_command = "exec opencode"
ready_delay_ms = 0

[defaults]
[defaults.rig]

[[rigs]]
name = "demo-app"
default_branch = "master"

[[patches.agent]]
name = "gastown.polecat"
dir = "demo-app"
max_active_sessions = 1

[daemon]
patrol_interval = "60s"
probe_concurrency = 1
max_wakes_per_tick = 1

[orders]
skip = ["dolt-health"]

[[orders.overrides]]
name = "reaper"
trigger = "manual"
''';

ProcessResult _sh(String script, {String? cwd, Map<String, String>? env}) =>
    Process.runSync(
      'sh',
      ['-c', script],
      workingDirectory: cwd,
      environment: env,
      includeParentEnvironment: env == null,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('start times', () {
    test('a new team gives an agent minutes to start, not 30 s', () {
      final tuning = BuiltinTeam.phoneTuning;
      expect(tuning, contains('[session]\nstartup_timeout = "4m"\n'));
      expect(
        tuning,
        contains('[session.acp]\n${BuiltinTeam.handshakeTimeout}\n'),
      );
      expect(BuiltinTeam.cityScript, contains(tuning));
    });

    test('a team tuned by the previous version gets them on its next '
        'start, the rest of it kept', () {
      final dir = Directory.systemTemp.createTempSync('oc-hot-tune');
      addTearDown(() => dir.deleteSync(recursive: true));
      final city = File('${dir.path}/city.toml')
        ..writeAsStringSync(_previousCity);
      final script = BuiltinTeam.tuneScript.replaceAll(
        BuiltinTeam.cityDir,
        dir.path,
      );
      final first = _sh('set -eu\n$script');
      expect(first.exitCode, 0, reason: '${first.stderr}');
      final tuned = city.readAsStringSync();
      expect(tuned, contains('[session.acp]\nhandshake_timeout = "3m"\n'));
      expect(tuned, contains('[session]\nstartup_timeout = "4m"\n'));
      for (final header in [
        r'\[session\]',
        r'\[session\.acp\]',
        r'\[daemon\]',
      ]) {
        expect(
          RegExp('^$header\$', multiLine: true).allMatches(tuned),
          hasLength(1),
          reason: header,
        );
      }
      expect('acp_command'.allMatches(tuned), hasLength(1));
      for (final kept in [
        'name = "demo-app"',
        'default_branch = "master"',
        'max_active_sessions = 1',
        'ready_delay_ms = 0',
      ]) {
        expect(tuned, contains(kept));
      }
      // The next start changes nothing.
      final second = _sh('set -eu\n$script');
      expect(second.exitCode, 0, reason: '${second.stderr}');
      expect(city.readAsStringSync(), tuned);
      final toml = Process.runSync('python3', [
        '-c',
        'import sys, tomllib\n'
            'c = tomllib.load(open(sys.argv[1], "rb"))\n'
            'print(c["session"]["startup_timeout"], '
            'c["session"]["acp"]["handshake_timeout"])',
        city.path,
      ]);
      if (toml.exitCode != 127 && !'${toml.stderr}'.contains('No module')) {
        expect(toml.exitCode, 0, reason: '${toml.stderr}');
        expect('${toml.stdout}'.trim(), '4m 3m');
      }
    });
  });

  group("the agents' opencode", () {
    late Directory root;
    late String home;
    late String worktree;
    late String fake;
    late String wrapper;

    setUp(() {
      root = Directory.systemTemp.createTempSync('oc-hot-wrapper');
      home = '${root.path}/home';
      worktree = '$home/aiteam/city/.gc/worktrees/demo-app/polecats/furiosa';
      Directory('$worktree/.opencode/plugins').createSync(recursive: true);
      File(
        '$worktree/.opencode/plugins/gascity.js',
      ).writeAsStringSync('export default {}\n');
      // A git folder already, so the worktree step is skipped.
      Directory('$worktree/.git').createSync();
      // The real OpenCode stands in as a program that says how it was run.
      fake = '${root.path}/opencode2';
      File(fake).writeAsStringSync(
        '#!/bin/sh\n'
        'echo "args=\$*"\n'
        'echo "models_fetch_off=\${OPENCODE_DISABLE_MODELS_FETCH:-}"\n',
      );
      Process.runSync('chmod', ['755', fake]);
      wrapper = '${root.path}/wrapper';
      File(wrapper).writeAsStringSync(
        AiTeamScripts.agentWrapperScript.replaceAll(
          '/usr/local/bin/opencode2',
          fake,
        ),
      );
      Process.runSync('chmod', ['755', wrapper]);
    });

    tearDown(() => root.deleteSync(recursive: true));

    ProcessResult run() => Process.runSync(
      wrapper,
      ['acp'],
      workingDirectory: worktree,
      environment: {'HOME': home, 'PATH': '/usr/bin:/bin'},
      includeParentEnvironment: false,
    );

    test(
      'launches OpenCode 2 without fetching models or rewriting packages',
      () {
        final result = run();
        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect('${result.stdout}', contains('args=acp'));
        expect('${result.stdout}', contains('models_fetch_off=1'));
        expect(File('$worktree/.opencode/package.json').existsSync(), isFalse);
        expect(
          File('$worktree/.opencode/package-lock.json').existsSync(),
          isFalse,
        );
        expect(
          FileSystemEntity.typeSync(
            '$worktree/.opencode/node_modules',
            followLinks: false,
          ),
          FileSystemEntityType.notFound,
        );
        expect(
          File('$worktree/.opencode/plugins/gascity.js').readAsStringSync(),
          'export default {}\n',
        );
      },
    );

    test('a project\'s own .opencode with a package.json is not touched', () {
      const own = '{"dependencies": {"left-pad": "1.3.0"}}\n';
      File('$worktree/.opencode/package.json').writeAsStringSync(own);
      final result = run();
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(File('$worktree/.opencode/package.json').readAsStringSync(), own);
      expect(
        FileSystemEntity.typeSync(
          '$worktree/.opencode/node_modules',
          followLinks: false,
        ),
        FileSystemEntityType.notFound,
      );
      expect(
        File('$worktree/.opencode/package-lock.json').existsSync(),
        isFalse,
      );
    });

    test('every team start brings an older wrapper up to date', () {
      final bin = Directory('${root.path}/agent-bin')..createSync();
      final installed = File('${bin.path}/opencode')
        ..writeAsStringSync('#!/bin/sh\nexec /usr/local/bin/opencode "\$@"\n');
      final script = AiTeamScripts.refreshAgentWrapperScript.replaceAll(
        AiTeamScripts.agentBin,
        bin.path,
      );
      final result = _sh('set -eu\n$script');
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(installed.readAsStringSync(), AiTeamScripts.agentWrapperScript);
      expect(installed.statSync().modeString(), 'rwxr-xr-x');
      expect(bin.listSync(), hasLength(1));
      expect(
        BuiltinTeam.serviceScript.indexOf(
          AiTeamScripts.refreshAgentWrapperScript,
        ),
        allOf(
          greaterThan(0),
          lessThan(BuiltinTeam.serviceScript.indexOf('exec gc supervisor run')),
        ),
      );
      // Not installed: nothing is made.
      final none = AiTeamScripts.refreshAgentWrapperScript.replaceAll(
        AiTeamScripts.agentBin,
        '${root.path}/missing',
      );
      expect(_sh('set -eu\n$none').exitCode, 0);
      expect(Directory('${root.path}/missing').existsSync(), isFalse);
    });
  });

  group('agent starts', () {
    // Lines as Gas City 1.4.1 prints them (logLifecycleOutcome).
    const log =
        'gc supervisor: city phone running\n'
        'session lifecycle: op=start wave=1 session=gastown__polecat-ph-n65 '
        'template=demo-app/gastown.polecat outcome=deadline_exceeded '
        'duration=31.874s phases=[start_call=31.702s] '
        'err=acp handshake for "gastown__polecat-ph-n65": initialize timeout: '
        r'context deadline exceeded\nagent stderr:\nINFO boot'
        '\n'
        'session lifecycle: op=start wave=1 session=gastown__polecat-ph-yqt '
        'template=demo-app/gastown.polecat outcome=success duration=22.01s '
        'phases=[start_call=21.9s post_start_observe=105ms]\n';

    test('are read from the supervisor log, oldest first', () async {
      debugPlatformCapabilities = const PlatformCapabilities(
        platform: TargetPlatform.android,
        isWeb: false,
      );
      addTearDown(() => debugPlatformCapabilities = null);
      const channel = MethodChannel(BuiltinLinux.channelName);
      final asked = <Object?>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            asked.add(call.arguments);
            return call.method == 'serviceLog' ? log : null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final starts = await BuiltinTeam(linux: BuiltinLinux()).agentStarts();
      expect(asked.single, {'name': 'aiteam', 'tailBytes': 65536});
      expect(starts, hasLength(2));
      final cut = starts.first;
      expect(cut.session, 'gastown__polecat-ph-n65');
      expect(cut.template, 'demo-app/gastown.polecat');
      expect(cut.succeeded, isFalse);
      expect(cut.timedOut, isTrue);
      expect(cut.duration, const Duration(milliseconds: 31874));
      expect(cut.startCall, const Duration(milliseconds: 31702));
      expect(cut.error, contains('initialize timeout'));
      expect(cut.error, contains('\nagent stderr:\nINFO boot'));
      final ok = starts.last;
      expect(ok.succeeded, isTrue);
      expect(ok.timedOut, isFalse);
      expect(ok.duration, const Duration(milliseconds: 22010));
      expect(ok.startCall, const Duration(milliseconds: 21900));
      expect(ok.error, isNull);
    });

    test('Go durations', () {
      for (final (text, value) in [
        ('850ms', const Duration(milliseconds: 850)),
        ('22.345s', const Duration(milliseconds: 22345)),
        ('1m2.5s', const Duration(minutes: 1, milliseconds: 2500)),
        ('1h0m0s', const Duration(hours: 1)),
        ('0s', Duration.zero),
      ]) {
        expect(
          BuiltinTeamAgentStart.parseGoDuration(text),
          value,
          reason: text,
        );
      }
      for (final bad in [null, '', 'soon', '5 s', '1m?']) {
        expect(BuiltinTeamAgentStart.parseGoDuration(bad), isNull);
      }
    });
  });
}
