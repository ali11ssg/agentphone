import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/api2/client.dart';
import 'package:agentphone/api2/gateway.dart';
import 'package:agentphone/api2/shell_runner.dart';
import 'package:agentphone/api2/transport.dart';
import 'package:agentphone/domain/git/git_shell.dart';
import 'package:agentphone/domain/remote_shell.dart';
import 'package:agentphone/domain/server_gateway.dart';
import 'package:agentphone/state/git_workspace.dart';

/// `/api/shell` as protocol notes §10 describe it.
class _Server implements HttpClientAdapter {
  _Server({this.createStatus = 200});

  final int createStatus;
  final String output = 'hello world';
  final requests = <({String method, String path, Map query, Object? body})>[];
  var polls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final raw = requestStream == null
        ? ''
        : utf8.decode(await requestStream.expand((c) => c).toList());
    final path = options.uri.path.replaceFirst('/api', '');
    requests.add((
      method: options.method,
      path: path,
      query: options.uri.queryParameters,
      body: raw.isEmpty ? null : jsonDecode(raw),
    ));
    ResponseBody json(Object body, [int status = 200]) =>
        ResponseBody.fromString(
          jsonEncode(body),
          status,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        );
    Map info(String status) => {
      'id': 'sh_1',
      'status': status,
      'command': 'x',
      'cwd': '/p',
      'shell': '/bin/sh',
      'file': '/tmp/f',
      'metadata': {},
      'time': {'started': 1},
      if (status != 'running') 'exit': 0,
    };
    switch ((options.method, path)) {
      case ('POST', '/shell'):
        if (createStatus != 200) {
          return json({'_tag': 'NotFound', 'message': 'no'}, createStatus);
        }
        return json({'location': {}, 'data': info('running')});
      case ('GET', '/shell/sh_1'):
        polls++;
        return json({
          'location': {},
          'data': info(polls < 3 ? 'running' : 'exited'),
        });
      case ('GET', '/shell/sh_1/output'):
        final cursor = int.parse(options.uri.queryParameters['cursor']!);
        final end = (cursor + 5).clamp(0, output.length);
        return json({
          'location': {},
          'data': {
            'output': output.substring(cursor, end),
            'cursor': end,
            'size': output.length,
            'truncated': false,
          },
        });
      case ('DELETE', '/shell/sh_1'):
        return json({});
      case ('GET', '/info'):
        return json({'message': 'not found'}, 404);
    }
    throw StateError('unexpected ${options.method} $path');
  }

  @override
  void close({bool force = false}) {}
}

Api2Client _client(_Server server) {
  final transport = Api2Transport(
    baseUrl: 'http://127.0.0.1:9',
    password: 'fake-test-password',
  );
  transport.dio.httpClientAdapter = server;
  return Api2Client(transport: transport, directory: '/root/projects/app');
}

void main() {
  test('starts, polls, pages the output and drops it', () async {
    final server = _Server();
    final runner = Api2ShellRunner(_client(server), sleep: (_) async {});
    final result = await runner.runShellCommand(
      "sh -c 'git status'",
      timeout: const Duration(seconds: 30),
    );
    expect(result.output, 'hello world');
    expect(result.exitCode, 0);
    expect(result.status, RemoteShellStatus.exited);
    final create = server.requests.first;
    expect(create.method, 'POST');
    expect(create.path, '/shell');
    expect(create.query['location[directory]'], '/root/projects/app');
    expect(create.body, {
      'command': "sh -c 'git status'",
      'cwd': '/root/projects/app',
      'timeout': 30000,
    });
    expect(server.polls, 3);
    final pages = server.requests.where((r) => r.path.endsWith('/output'));
    expect(pages.map((r) => r.query['cursor']), ['0', '5', '10']);
    await Future<void>.delayed(Duration.zero);
    expect(server.requests.last.method, 'DELETE');
  });

  test('no endpoint (404) is "unsupported", without server text', () async {
    final runner = Api2ShellRunner(
      _client(_Server(createStatus: 404)),
      sleep: (_) async {},
    );
    await expectLater(
      runner.runShellCommand('x', timeout: const Duration(seconds: 1)),
      throwsA(
        isA<RemoteShellException>()
            .having((e) => e.failure, 'failure', RemoteShellFailure.unsupported)
            .having((e) => e.toString(), 'text', isNot(contains('no'))),
      ),
    );
  });

  test('OpenCode 2 reports the capability and implements the gateway', () {
    final gateway = Api2Gateway(client: _client(_Server()));
    expect(gateway.capabilities.remoteShell, isTrue);
    expect(gateway, isA<RemoteShellGateway>());
    expect(const ServerCapabilities().remoteShell, isFalse);
  });

  test('the server shell wraps the script in sh -c, quoted', () async {
    final gateway = _RecordingGateway();
    final shell = ServerGitShell(gateway, directory: '/p');
    final out = await shell.run(
      "echo 'it''s'",
      timeout: const Duration(seconds: 5),
    );
    expect(out, 'ok');
    expect(gateway.commands.single, "sh -c 'echo '\\''it'\\'''\\''s'\\'''");
    gateway.status = RemoteShellStatus.timedOut;
    await expectLater(
      shell.run('x', timeout: const Duration(seconds: 1)),
      throwsA(
        isA<GitShellException>().having(
          (e) => e.failure,
          'failure',
          GitShellFailure.timedOut,
        ),
      ),
    );
  });
}

class _RecordingGateway implements RemoteShellGateway {
  final commands = <String>[];
  var status = RemoteShellStatus.exited;

  @override
  Future<RemoteShellResult> runShellCommand(
    String command, {
    String? directory,
    required Duration timeout,
  }) async {
    commands.add(command);
    return RemoteShellResult(status: status, output: 'ok', exitCode: 0);
  }
}
