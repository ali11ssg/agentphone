import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A loopback-only, read-only OpenCode 2 fixture. No model or provider credentials.
class Bd9DeviceSmokeFixture {
  Bd9DeviceSmokeFixture._(this._server);

  final HttpServer _server;
  final reads = <String>{};
  final refusedWrites = <String>{};
  final unknownReads = <String>{};

  static const title = 'BD9 release conversation';
  static const sessionID = 'ses_bd9_smoke';
  static const directory = '/project/bd9';

  String get baseUrl => 'http://127.0.0.1:${_server.port}';

  static Future<Bd9DeviceSmokeFixture> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fixture = Bd9DeviceSmokeFixture._(server);
    server.listen(fixture._serve);
    return fixture;
  }

  Future<void> close() async => _server.close(force: true);

  static Map<String, Object?> get _session => {
    'id': sessionID,
    'location': {'directory': directory, 'projectID': 'bd9-project'},
    'title': title,
    'time': {'created': 1791324000000, 'updated': 1791324000000},
  };

  Future<void> _serve(HttpRequest request) async {
    final path = request.uri.path;
    if (request.method != 'GET') {
      refusedWrites.add(path);
      request.response.statusCode = HttpStatus.methodNotAllowed;
      request.response.write('{"error":"read_only_fixture"}');
      await request.response.close();
      return;
    }
    reads.add(path);
    if (path == '/api/event') {
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
      );
      request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      final event = {
        'type': 'server.connected',
        'data': <String, Object>{},
        'durable': false,
      };
      request.response.write('data: ${jsonEncode(event)}\n\n');
      await request.response.flush();
      // Deliberately keep the real SSE connection open until close(force:true).
      return;
    }

    final Object? data = switch (path) {
      '/api/health' => {'healthy': true, 'version': '0.0.0-beta-18600'},
      // The global inventory's root filter distinguishes it from scoped reads.
      '/api/session' => {
        'data': request.uri.queryParameters['parentID'] == 'null'
            ? [_session]
            : <Object>[],
        'cursor': <String, Object>{},
      },
      '/api/session/active' => {'data': <String, Object>{}},
      '/api/project' => {
        'data': [
          {
            'id': 'bd9-project',
            'directory': directory,
            'name': 'BD9 project',
            'time': {'created': 1791324000000, 'updated': 1791324000000},
          },
        ],
      },
      '/api/provider' ||
      '/api/model' ||
      '/api/agent' ||
      '/api/integration' ||
      '/api/permission/request' ||
      '/api/form/request' ||
      '/api/command' ||
      '/api/skill' ||
      '/api/reference' ||
      '/api/config' ||
      '/api/mcp' => {'data': []},
      '/api/vcs' => {
        'data': {
          'branch': {'current': 'bd9'},
        },
      },
      _ => null,
    };
    request.response.headers.contentType = ContentType.json;
    if (data == null) {
      unknownReads.add(path);
      request.response.statusCode = HttpStatus.notFound;
      request.response.write('{"error":"fixture_route_missing"}');
    } else {
      request.response.write(jsonEncode(data));
    }
    await request.response.close();
  }
}
