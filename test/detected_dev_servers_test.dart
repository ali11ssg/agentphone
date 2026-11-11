import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/domain/listening_ports.dart';
import 'package:agentphone/domain/managed_shell.dart';
import 'package:agentphone/state/detected_dev_servers.dart';
import 'package:agentphone/state/dev_server_scan.dart';
import 'package:agentphone/state/profiles.dart';

import 'support/development_service_fakes.dart';

const _row =
    '   0: 0100007F:1435 00000000:0000 0A 00000000:00000000 00:00000000 '
    '00000000  1000        0 5001 1 0000000000000000 100 0 0 10 0';
const _row2 =
    '   1: 00000000:1F90 00000000:0000 0A 00000000:00000000 00:00000000 '
    '00000000  1000        0 5002 1 0000000000000000 100 0 0 10 0';

String _phoneOutput({String log = '/root/p/dev.log'}) =>
    '''
#T4
$_row
$_row2
#S
lrwx------ 1 root root 64 Oct 16 10:00 /proc/41/fd/3 -> socket:[5001]
lrwx------ 1 root root 64 Oct 16 10:00 /proc/42/fd/3 -> socket:[5002]
#C
41\tnode vite --port 5173 \t/root/p\t$log
42\tpython3 -m http.server 8080 \t/other\t/dev/pts/0
#P
''';

ManagedShell _shell(String id, String command, {bool running = true}) =>
    ManagedShell(
      id: id,
      command: command,
      status: running ? ManagedShellStatus.running : ManagedShellStatus.exited,
      startedAt: DateTime.fromMillisecondsSinceEpoch(1000),
      directory: '/root/p',
    );

void main() {
  late ServiceRepository repo;
  late List<String> scripts;
  var exit = 0;
  var output = '';

  DetectedDevServers make({
    bool phone = true,
    Set<String> owned = const {},
    DateTime Function()? now,
  }) => DetectedDevServers(
    directory: '/root/p',
    resolveGateway: () async => repo,
    isCurrent: () => true,
    ownedShellIds: () => owned,
    now: now ?? DateTime.now,
    runOnPhone: phone
        ? (script) async {
            scripts.add(script);
            return (exitCode: exit, output: output);
          }
        : null,
  );

  setUp(() {
    repo = ServiceRepository();
    scripts = [];
    exit = 0;
    output = _phoneOutput();
  });

  test(
    'a program listening on the phone is listed with port and logs',
    () async {
      final detected = make();
      await detected.refresh();
      expect(detected.scanned, isTrue);
      expect(detected.servers.map((s) => s.firstPort), [5173, 8080]);
      final vite = detected.servers.first;
      expect(vite.name, 'vite');
      expect(vite.pid, 41);
      expect(vite.hasLogs, isTrue);
      expect(vite.canStop, isTrue);
      expect(detected.servers.last.hasLogs, isFalse);
      expect(detected.forPort(8080)?.pid, 42);
      expect(detected.allPorts, [5173, 8080]);
    },
  );

  test(
    'a server shell is listed with the ports its own output printed',
    () async {
      repo.shells['sh_1'] = _shell('sh_1', 'npm run dev');
      final detected = make(phone: false);
      await detected.refresh();
      final shell = detected.servers.single;
      expect(shell.source, DetectedSource.shell);
      expect(shell.shellId, 'sh_1');
      expect(shell.ports, [
        5173,
      ], reason: 'from "Local: http://localhost:5173/"');
      expect(shell.hasLogs, isTrue);
      expect(detected.canScanProcesses, isFalse);
      expect(scripts, isEmpty, reason: 'no phone, no script');
    },
  );

  test(
    'a program that is already a listed shell is not listed twice',
    () async {
      repo.shells['sh_1'] = _shell('sh_1', 'npm run dev');
      final detected = make();
      await detected.refresh();
      expect(detected.allPorts, [5173, 8080]);
      expect(
        detected.servers.where((s) => s.source == DetectedSource.shell),
        hasLength(1),
      );
      expect(
        detected.servers.where((s) => s.ports.contains(5173)),
        hasLength(1),
      );
    },
  );

  test(
    'a shell a saved command owns is not listed but its ports are known',
    () async {
      repo.shells['sh_1'] = _shell('sh_1', 'npm run dev');
      final detected = make(owned: {'sh_1'}, phone: false);
      await detected.refresh();
      expect(detected.servers, isEmpty);
      expect(detected.portsForShell('sh_1'), [5173]);
    },
  );

  test('servers in the project folder come first', () async {
    output = _phoneOutput()
        .replaceAll('/other', '/root/p')
        .replaceAll('\t/root/p\t/root/p/dev.log', '\t/elsewhere\t/dev/null');
    final detected = make();
    await detected.refresh();
    expect(detected.servers.first.firstPort, 8080);
  });

  test('a shell that ended is not listed', () async {
    repo.shells['sh_1'] = _shell('sh_1', 'npm run dev', running: false);
    final detected = make(phone: false);
    await detected.refresh();
    expect(detected.servers, isEmpty);
  });

  test('a failed phone script keeps shells and records the failure', () async {
    repo.shells['sh_1'] = _shell('sh_1', 'npm run dev');
    final detected = DetectedDevServers(
      directory: '/root/p',
      resolveGateway: () async => repo,
      isCurrent: () => true,
      runOnPhone: (_) async => throw StateError('no linux'),
    );
    await detected.refresh();
    expect(detected.servers, hasLength(1));
    expect(detected.error, isNotNull);
    expect(detected.scanned, isTrue);
  });

  test('a look that fails while its own stop runs keeps the list and '
      'reports nothing', () async {
    final stopStarted = Completer<void>();
    final finishStop = Completer<void>();
    var lookFails = false;
    final detected = DetectedDevServers(
      directory: '/root/p',
      resolveGateway: () async => repo,
      isCurrent: () => true,
      runOnPhone: (script) async {
        if (script.contains('kill')) {
          stopStarted.complete();
          lookFails = true;
          await finishStop.future;
          lookFails = false;
          return (exitCode: 0, output: '');
        }
        if (lookFails) throw StateError('phone busy');
        return (exitCode: 0, output: _phoneOutput());
      },
    );
    await detected.refresh();
    final vite = detected.servers.firstWhere((s) => s.pid == 41);
    final stopping = detected.stop(vite);
    await stopStarted.future;
    await detected.refresh();
    expect(detected.error, isNull);
    expect(detected.servers, hasLength(2), reason: 'the last list stays');
    finishStop.complete();
    await stopping;
    expect(detected.error, isNull);
  });

  test('a stale answer after invalidate is dropped', () async {
    final detected = make();
    final pending = detected.refresh();
    detected.invalidate();
    await pending;
    expect(detected.servers, isEmpty);
    expect(detected.scanned, isFalse);
  });

  test('a shell\'s log is its output tail with colour codes removed', () async {
    repo.output = '\x1B[32mready\x1B[0m\nLocal: http://localhost:5173/\n';
    repo.shells['sh_1'] = _shell('sh_1', 'npm run dev');
    final detected = make(phone: false);
    await detected.refresh();
    final text = await detected.readLog(detected.servers.single);
    expect(text, 'ready\nLocal: http://localhost:5173/\n');
  });

  test('a program\'s log is read from its output file', () async {
    final detected = make();
    await detected.refresh();
    output = 'line one\n\x1B[31mline two\x1B[0m\n';
    final text = await detected.readLog(detected.servers.first);
    expect(text, 'line one\nline two\n');
    expect(scripts.last, contains("tail -c 65536 -- '/root/p/dev.log'"));
  });

  test('a program with no log file cannot be read', () async {
    final detected = make();
    await detected.refresh();
    expect(
      () => detected.readLog(detected.servers.last),
      throwsA(isA<StateError>()),
    );
  });

  test('stopping a shell asks the server and drops the row', () async {
    repo.shells['sh_1'] = _shell('sh_1', 'npm run dev');
    final detected = make(phone: false);
    await detected.refresh();
    await detected.stop(detected.servers.single);
    expect(repo.stops, ['sh_1']);
    expect(detected.servers, isEmpty);
  });

  test('stopping a program runs the guarded kill for that pid only', () async {
    final detected = make();
    await detected.refresh();
    final vite = detected.servers.first;
    scripts.clear();
    output = '';
    await detected.stop(vite);
    expect(scripts.first, ListeningPorts.stopScript(41, vite.command));
    expect(scripts.first, contains('kill -TERM 41'));
  });

  test('a stop that did not work says so and keeps the row', () async {
    final detected = make();
    await detected.refresh();
    exit = 5;
    await expectLater(
      detected.stop(detected.servers.first),
      throwsA(isA<StateError>()),
    );
    expect(detected.servers, isNotEmpty);
  });

  group('who can be scanned', () {
    ServerProfile profile(String url) =>
        ServerProfile(id: 'p', name: 'P', baseUrl: url);

    test('only the phone itself, where the in-app Linux exists', () {
      expect(
        phoneScriptRunner(profile('http://127.0.0.1:4097'), supported: true),
        isNotNull,
      );
      expect(
        phoneScriptRunner(profile('http://localhost:4097'), supported: true),
        isNotNull,
      );
      expect(
        phoneScriptRunner(profile('http://192.168.1.20:4097'), supported: true),
        isNull,
      );
      expect(
        phoneScriptRunner(profile('http://127.0.0.1:4097'), supported: false),
        isNull,
      );
      expect(phoneScriptRunner(null, supported: true), isNull);
    });
  });
}
