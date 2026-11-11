// The one-shot check's terminal on the wire: OpenCode 2 creates a
// PTY with the command and arguments as separate fields, keep the check out
// of the person's terminal list, and map the failures a server can give.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/domain/product_repository.dart';
import 'package:agentphone/api2/client.dart';
import 'package:agentphone/api2/gateway_operations.dart';
import 'package:agentphone/domain/terminal_lifecycle.dart';
import 'package:agentphone/domain/usage_subscriptions.dart';
import 'package:agentphone/state/computer_usage_source.dart';

class _RealHttpOverrides extends HttpOverrides {}

Map<String, Object?> _pty(String id, String title) => {
  'id': id,
  'title': title,
  'command': 'node',
  'args': ['--input-type=module', '-e', 'S'],
  'cwd': '/project',
  'status': 'running',
  'pid': 18,
};

Future<void> _withServer(
  Future<void> Function(HttpRequest request) handler,
  Future<void> Function(String baseUrl) test,
) async {
  await HttpOverrides.runZoned(() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(handler);
    try {
      await test('http://${server.address.host}:${server.port}');
    } finally {
      await server.close(force: true);
    }
  }, createHttpClient: (_) => _RealHttpOverrides().createHttpClient(null));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OpenCode 2', () {
    Future<void> withGateway(
      Future<void> Function(HttpRequest) handler,
      Future<void> Function(ServerOperationsGateway gateway) test,
    ) => _withServer(handler, (baseUrl) async {
      final client = Api2Client.connect(
        baseUrl: baseUrl,
        password: 'fake-test-password',
        directory: '/project',
      );
      try {
        await test(Api2OperationsGateway(client: client));
      } finally {
        client.close();
      }
    });

    test('creates a PTY with the command and arguments apart', () async {
      final bodies = <dynamic>[];
      await withGateway(
        (request) async {
          bodies.add(jsonDecode(await utf8.decoder.bind(request).join()));
          request.response.headers.contentType = ContentType.json;
          final json = _pty('pty_1', computerUsageTitle);
          request.response.write(jsonEncode({'data': json}));
          await request.response.close();
        },
        (gateway) async {
          expect(gateway, isA<OneShotCommandGateway>());
          final port = GatewayComputerTerminalPort(gateway);
          final process = await port.start('node', [
            '--input-type=module',
            '-e',
            'SOURCE with "quotes" and \n lines',
          ], title: computerUsageTitle);
          expect(process.id, 'pty_1');
          expect(bodies.single['command'], 'node');
          expect(bodies.single['args'], [
            '--input-type=module',
            '-e',
            'SOURCE with "quotes" and \n lines',
          ]);
          expect(bodies.single['title'], computerUsageTitle);
        },
      );
    });

    test('leaves the usage check out of the terminal list', () async {
      await withGateway(
        (request) async {
          await request.drain<void>();
          request.response.headers.contentType = ContentType.json;
          final list = [
            _pty('pty_mine', 'Build'),
            _pty('pty_check', computerUsageTitle),
          ];
          request.response.write(jsonEncode({'data': list}));
          await request.response.close();
        },
        (gateway) async {
          final terminals = await gateway.listTerminals();
          expect(terminals.map((t) => t.id), ['pty_mine']);
        },
      );
    });

    test('failures map to fixed reasons without server text', () async {
      for (final (status, expected) in [
        (404, ComputerUsageProblem.serverTooOld),
        (405, ComputerUsageProblem.serverTooOld),
        (500, ComputerUsageProblem.nodeMissing),
      ]) {
        await withGateway(
          (request) async {
            await request.drain<void>();
            request.response.statusCode = status;
            request.response.write('fake-sensitive-server-detail');
            await request.response.close();
          },
          (gateway) async {
            final port = GatewayComputerTerminalPort(gateway);
            await expectLater(
              port.start('node', const [], title: computerUsageTitle),
              throwsA(
                isA<ComputerUsageException>()
                    .having((e) => e.problem, 'problem', expected)
                    .having(
                      (e) => e.toString(),
                      'text',
                      isNot(contains('sensitive')),
                    ),
              ),
            );
          },
        );
      }
    });

    test('no answer at all is "unreachable"', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final baseUrl = 'http://${server.address.host}:${server.port}';
      await server.close(force: true);
      await HttpOverrides.runZoned(() async {
        final client = Api2Client.connect(
          baseUrl: baseUrl,
          password: 'fake-test-password',
          directory: '/project',
        );
        try {
          final gateway = Api2OperationsGateway(client: client);
          await expectLater(
            GatewayComputerTerminalPort(
              gateway,
            ).start('node', const [], title: computerUsageTitle),
            throwsA(
              isA<ComputerUsageException>().having(
                (e) => e.problem,
                'problem',
                ComputerUsageProblem.unreachable,
              ),
            ),
          );
        } finally {
          client.close();
        }
      }, createHttpClient: (_) => _RealHttpOverrides().createHttpClient(null));
    });
  });

  test('a gateway without the facet is "too old", not a crash', () async {
    final port = GatewayComputerTerminalPort(_Bare());
    await expectLater(
      port.start('node', const [], title: computerUsageTitle),
      throwsA(
        isA<ComputerUsageException>().having(
          (e) => e.problem,
          'problem',
          ComputerUsageProblem.serverTooOld,
        ),
      ),
    );
  });
}

class _Bare implements ServerOperationsGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
