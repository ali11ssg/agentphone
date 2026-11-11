import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/domain/ansi_text.dart';
import 'package:agentphone/domain/listening_ports.dart';
import 'package:agentphone/state/detected_dev_servers.dart';

// A LISTEN row of /proc/net/tcp: port 5173 (0x1435) on 127.0.0.1, inode 5001.
const _vite =
    '   0: 0100007F:1435 00000000:0000 0A 00000000:00000000 00:00000000 '
    '00000000  1000        0 5001 1 0000000000000000 100 0 0 10 0';
// Port 8080 (0x1F90) on all interfaces, inode 5002.
const _any =
    '   1: 00000000:1F90 00000000:0000 0A 00000000:00000000 00:00000000 '
    '00000000  1000        0 5002 1 0000000000000000 100 0 0 10 0';
// Port 4097 (0x1001): the in-app OpenCode server.
const _own =
    '   2: 0100007F:1001 00000000:0000 0A 00000000:00000000 00:00000000 '
    '00000000  1000        0 5003 1 0000000000000000 100 0 0 10 0';
// An established connection (state 01), not a listener.
const _established =
    '   3: 0100007F:1435 0100007F:C350 01 00000000:00000000 00:00000000 '
    '00000000  1000        0 5004 1 0000000000000000 100 0 0 10 0';
// IPv6 ::1 port 3000 (0x0BB8), inode 5005.
const _v6 =
    '   0: 00000000000000000000000001000000:0BB8 '
    '00000000000000000000000000000000:0000 0A 00000000:00000000 '
    '00:00000000 00000000  1000        0 5005 1 0000000000000000 100 0 0 10 0';

String _output({List<String> probe = const []}) =>
    '''
#T4
$_vite
$_any
$_own
#T6
$_v6
#S
lrwx------ 1 root root 64 Oct 16 10:00 /proc/41/fd/3 -> socket:[5001]
lrwx------ 1 root root 64 Oct 16 10:00 /proc/42/fd/7 -> socket:[5002]
lrwx------ 1 root root 64 Oct 16 10:00 /proc/43/fd/7 -> socket:[5003]
lrwx------ 1 root root 64 Oct 16 10:00 /proc/44/fd/9 -> socket:[5005]
#C
41\tnode /root/projects/shop/node_modules/.bin/vite --port 5173 \t/root/projects/shop\t/root/projects/shop/dev.log
42\tpython3 -m http.server 8080 \t/root/projects/shop\t/dev/pts/0
43\topencode serve --port 4097 \t/root\tpipe:[1]
44\tnode server.js \t/root/other\tpipe:[2]
#P
${probe.join('\n')}
''';

void main() {
  group('parsing', () {
    test('a LISTEN row gives the port, inode and whether it is loopback', () {
      final a = ListeningPorts.parseSocketLine(_vite)!;
      expect((a.port, a.inode, a.loopbackOnly), (5173, 5001, true));
      final b = ListeningPorts.parseSocketLine(_any)!;
      expect((b.port, b.loopbackOnly), (8080, false));
      final c = ListeningPorts.parseSocketLine(_v6)!;
      expect((c.port, c.loopbackOnly), (3000, true));
    });

    test('an established connection and a header are not listeners', () {
      expect(ListeningPorts.parseSocketLine(_established), isNull);
      expect(ListeningPorts.parseSocketLine('  sl  local_address'), isNull);
      expect(ListeningPorts.parseSocketLine(''), isNull);
    });

    test('processes come with ports, folder and log file', () {
      final found = ListeningPorts.parse(_output());
      expect(found.map((p) => p.pid), [41, 42, 44]);
      final vite = found.first;
      expect(vite.ports, [5173]);
      expect(vite.command, startsWith('node /root/projects/shop'));
      expect(vite.cwd, '/root/projects/shop');
      expect(vite.logPath, '/root/projects/shop/dev.log');
      expect(vite.loopbackOnly, isTrue);
      expect(found[1].logPath, isNull, reason: 'a terminal is not a file');
      expect(found[1].loopbackOnly, isFalse);
    });

    test('the in-app server and its own port are never listed', () {
      final found = ListeningPorts.parse(_output());
      expect(found.expand((p) => p.ports), isNot(contains(4097)));
      expect(
        found.map((p) => p.command),
        isNot(contains(startsWith('opencode'))),
      );
    });

    test('a probed port with no process is listed once, without a pid', () {
      final found = ListeningPorts.parse(
        _output(probe: ['5173', '4200', '4097']),
      );
      final extra = found.where((p) => !p.hasProcess).toList();
      expect(extra.map((p) => p.ports.single), [4200]);
      expect(extra.single.command, '');
    });

    test('hidden socket tables leave only what the probe found', () {
      final found = ListeningPorts.parse('#T4\n#T6\n#S\n#C\n#P\n3000\n');
      expect(found.map((p) => p.ports.single), [3000]);
    });

    test('without tables, a probed port goes to the process that named it', () {
      const out =
          '#T4\n#T6\n#S\n#C\n'
          '50\tpython3 -m http.server 8765 \t/root/projects/app\t/dev/null\n'
          '51\tcurl http://127.0.0.1:8765/ \t/root\tpipe:[1]\n'
          '52\tpaseo daemon --port 6767 \t/root\tpipe:[2]\n'
          '::n 50 8765\n::n 51 8765\n::n 52 6767\n'
          '#P\n8765\n6767\n3000\n';
      final found = ListeningPorts.parse(out);
      expect(found.map((p) => '${p.pid}:${p.ports.join(',')}'), [
        '50:8765',
        '0:3000',
      ]);
      expect(found.first.cwd, '/root/projects/app');
    });

    test('garbage and an empty answer give an empty list', () {
      expect(ListeningPorts.parse(''), isEmpty);
      expect(ListeningPorts.parse('bash: ls: not found\n'), isEmpty);
    });
  });

  group('scripts', () {
    test('the listing script reads the tables and probes the common ports', () {
      final script = ListeningPorts.script();
      expect(script, contains('/proc/net/tcp'));
      expect(script, contains('/proc/net/tcp6'));
      expect(script, contains('/dev/tcp/127.0.0.1/'));
      for (final port in commonDevPorts) {
        expect(script, contains('$port'));
      }
    });

    test('tail refuses anything that is not a plain file path', () {
      expect(ListeningPorts.tailScript('/dev/pts/0'), 'exit 2');
      expect(ListeningPorts.tailScript('/proc/1/fd/1'), 'exit 2');
      expect(ListeningPorts.tailScript('pipe:[3]'), 'exit 2');
      expect(
        ListeningPorts.tailScript('/tmp/a b.log'),
        contains("'/tmp/a b.log'"),
      );
    });

    test('a quote in a path cannot end the quoting', () {
      final script = ListeningPorts.tailScript("/tmp/x'; rm -rf /; '.log");
      expect(script, contains(r"'\''"));
    });

    test('stop signals one pid only while its command is unchanged', () {
      final script = ListeningPorts.stopScript(41, 'node vite --port 5173');
      expect(script, contains('kill -TERM 41'));
      expect(script, contains('kill -KILL 41'));
      expect(script, contains("'node vite --port 5173'*"));
      expect(ListeningPorts.stopScript(1, 'init'), 'exit 2');
      expect(ListeningPorts.stopScript(0, 'x'), 'exit 2');
    });

    test('ports are read from local links in a server\'s own output', () {
      expect(
        ListeningPorts.portsInOutput(
          'ready\n  Local: http://localhost:5173/\n  Network: http://0.0.0.0:5173\n'
          'api on http://127.0.0.1:3001.\n',
        ),
        [3001, 5173],
      );
      expect(ListeningPorts.portsInOutput('no links here'), isEmpty);
    });
  });

  group('live run without the socket tables (Android 10+)', () {
    // Android denies apps /proc/net/tcp{,6} (N1-4, build 2400), and the
    // script runs under /bin/sh, which is dash on Ubuntu. This runs the real
    // script under sh on this machine with the tables hidden, against a
    // python http.server on a port no fixed list holds, started the way the
    // QA did it: in the background of a subshell that exits (an orphan).
    Future<int?> pythonServer(int port, {String? log}) async {
      final out = log ?? '/dev/null';
      final r = await Process.run('sh', [
        '-c',
        'cd "${Directory.systemTemp.path}" && '
            '(python3 -m http.server $port --bind 127.0.0.1 >$out 2>&1 & echo \$!)',
      ]);
      final pid = int.tryParse((r.stdout as String).trim());
      if (pid == null) return null;
      for (var i = 0; i < 50; i++) {
        try {
          final s = await Socket.connect('127.0.0.1', port);
          s.destroy();
          return pid;
        } on SocketException {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
      Process.killPid(pid);
      return null;
    }

    Future<int> freePort() async {
      final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = s.port;
      await s.close();
      return port;
    }

    final hasPython =
        Platform.isLinux &&
        Process.runSync('sh', ['-c', 'command -v python3']).exitCode == 0;

    test(
      'finds python -m http.server on an arbitrary port, with its process',
      () async {
        final port = await freePort();
        final pid = await pythonServer(port);
        expect(pid, isNotNull, reason: 'python3 http.server did not start');
        try {
          final r = await Process.run('sh', [
            '-c',
            ListeningPorts.script(socketTables: const []),
          ]);
          final found = ListeningPorts.parse(r.stdout as String);
          final server = found.where((p) => p.ports.contains(port)).toList();
          expect(server, hasLength(1), reason: '${r.stdout}\n${r.stderr}');
          expect(server.single.pid, pid);
          expect(server.single.command, contains('http.server'));
        } finally {
          Process.killPid(pid!);
        }
      },
      skip: hasPython ? false : 'needs python3 on Linux',
    );

    test(
      'a port named only by PORT is found, and its log file is offered',
      () async {
        final port = await freePort();
        final dir = await Directory.systemTemp.createTemp('oc-ports');
        final log = '${dir.path}/server.log';
        // No number on the command line: http.server's default would be
        // 8000, so give it the port the way PORT-reading servers get it.
        final r0 = await Process.run(
          'sh',
          [
            '-c',
            'cd "${dir.path}" && (python3 -c "import http.server,os;'
                "http.server.test(HandlerClass=http.server.SimpleHTTPRequestHandler,"
                "port=int(os.environ['PORT']),bind='127.0.0.1')\" "
                '>$log 2>&1 & echo \$!)',
          ],
          environment: {'PORT': '$port'},
        );
        final pid = int.parse((r0.stdout as String).trim());
        try {
          for (var i = 0; i < 50; i++) {
            try {
              (await Socket.connect('127.0.0.1', port)).destroy();
              break;
            } on SocketException {
              await Future<void>.delayed(const Duration(milliseconds: 100));
            }
          }
          final r = await Process.run('sh', [
            '-c',
            ListeningPorts.script(socketTables: const []),
          ]);
          final found = ListeningPorts.parse(r.stdout as String);
          final server = found.where((p) => p.ports.contains(port)).toList();
          expect(server, hasLength(1), reason: '${r.stdout}\n${r.stderr}');
          expect(server.single.pid, pid);
          expect(server.single.logPath, log);
        } finally {
          Process.killPid(pid);
          await dir.delete(recursive: true);
        }
      },
      skip: hasPython ? false : 'needs python3 on Linux',
    );
  });

  group('names', () {
    test('a short name from a command line', () {
      expect(
        DetectedServer.nameFor('node /x/node_modules/.bin/vite --port 1'),
        'vite',
      );
      expect(
        DetectedServer.nameFor('python3 -m http.server 8080'),
        'http.server',
      );
      expect(DetectedServer.nameFor('npm run dev'), 'npm run dev');
      expect(DetectedServer.nameFor('/usr/bin/caddy run'), 'caddy');
      expect(DetectedServer.nameFor('   '), '');
    });
  });

  group('ansi', () {
    test('colour, cursor and title codes go; text and lines stay', () {
      expect(
        withoutTerminalCodes('\x1B[32mready\x1B[0m in 410 ms'),
        'ready in 410 ms',
      );
      expect(withoutTerminalCodes('\x1B]0;title\x07done'), 'done');
      expect(withoutTerminalCodes('a\r\nb\rc'), 'a\nb\nc');
      expect(withoutTerminalCodes('x\x1B[2K\x1B[1Gy'), 'xy');
      expect(withoutTerminalCodes('bell\x07 gone'), 'bell gone');
      expect(withoutTerminalCodes(''), '');
    });
  });
}
