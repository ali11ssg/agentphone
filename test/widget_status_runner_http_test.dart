import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/background/widget_action_runner.dart';
import 'package:agentphone/background/widget_status_runner.dart';
import 'package:agentphone/state/profiles.dart';

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final oc1 in [false]) {
    for (final busy in [true, false]) {
      test(
        'scheduled ${oc1 ? 'OC1' : 'OC2 stable'} read reports busy=$busy using only GET',
        () async {
          await HttpOverrides.runZoned(
            () async {
              final server = await HttpServer.bind(
                InternetAddress.loopbackIPv4,
                0,
              );
              final requests = <String>[];
              var statusReads = 0;
              final prefix = oc1 ? '' : '/api';
              server.listen((request) async {
                requests.add('${request.method} ${request.uri.path}');
                request.response.headers.contentType = ContentType.json;
                Object? body;
                switch (request.uri.path) {
                  case '/global/health':
                    body = {'healthy': true, 'version': '1.19.0'};
                  case '/api/health':
                    request.response.statusCode = 404;
                    body = {};
                  case '/api/info':
                    body = {'version': '2.0.29'};
                  case '/session/session/message':
                    body = [
                      {
                        'info': {
                          'id': 'user-1',
                          'sessionID': 'session',
                          'role': 'user',
                        },
                        'parts': [],
                      },
                    ];
                  case '/api/session/session/message':
                    body = {
                      'data': [
                        // Stable 2.0.29 appends an idle timeline message after
                        // the assistant finishes. The real gateway maps it to
                        // a v2:notice whose neutral MessageInfo role is user.
                        if (!busy)
                          {
                            'id': 'idle-1',
                            'type': 'idle',
                            'time': {'created': 4},
                          },
                        {
                          'id': 'notice-1',
                          'type': 'system',
                          'text': 'Synthetic notice',
                          'time': {'created': 3},
                        },
                        {
                          'id': 'user-1',
                          'type': 'user',
                          'text': 'Synthetic',
                          'time': {'created': 1},
                        },
                      ],
                    };
                  case '/session/status':
                  case '/api/session/active':
                    statusReads++;
                    final active = {
                      if (busy) 'session': {'type': oc1 ? 'busy' : 'running'},
                    };
                    body = oc1 ? active : {'data': active};
                  case '/permission':
                    body = [];
                  case '/api/permission/request':
                    body = {'data': []};
                  default:
                    request.response.statusCode = 404;
                    body = {};
                }
                request.response.write(jsonEncode(body));
                await request.response.close();
              });
              final profile = ServerProfile(
                id: 'profile',
                name: 'Synthetic',
                baseUrl: 'http://127.0.0.1:${server.port}',
                flavor: ServerFlavor.v2,
              );
              final fingerprint = widgetProfileFingerprint(profile);
              final target = <String, dynamic>{
                'profileID': 'profile',
                'scopeToken': 'scope',
                'fingerprint': fingerprint,
                'directory': '/synthetic/project',
              };
              final ticket = <String, dynamic>{
                ...target,
                'sessionID': 'session',
                'runMarker': 'user-1',
                'token': 'ticket',
              };
              final runner = WidgetStatusRunner(
                loadProfile: (_) async => profile,
                loadTarget: (_, _) async => target,
                isCurrent: (_) async => true,
              );
              try {
                expect(
                  await runner.check(
                    ticket,
                    DateTime.now().millisecondsSinceEpoch + 3000,
                  ),
                  {'status': busy ? 'busy' : 'idle'},
                );
                expect(statusReads, 1);
                expect(
                  requests.every((request) => request.startsWith('GET ')),
                  isTrue,
                );
                expect(
                  requests.where(
                    (request) =>
                        request == 'GET $prefix/session/session/message',
                  ),
                  hasLength(2),
                );
                expect(
                  requests.any((request) => request.contains('/event')),
                  isFalse,
                );
              } finally {
                runner.cancel();
                await server.close(force: true);
              }
            },
            createHttpClient: (_) =>
                _RealHttpOverrides().createHttpClient(null),
          );
        },
      );
    }
  }
}
