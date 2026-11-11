import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/api2/client.dart';
import 'package:agentphone/api2/gateway.dart';

void main() {
  test(
    'scoped v2 inventory opens newest first and retains cursor-only continuation',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final requests = <Uri>[];
      server.listen((request) async {
        requests.add(request.uri);
        final older = request.uri.queryParameters.containsKey('cursor');
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'data': [
              {
                'id': older ? 'older' : 'newest',
                'title': 'Session',
                'location': {'directory': '/work', 'workspaceID': 'workspace'},
                'time': {'created': 1, 'updated': 2},
              },
            ],
            'cursor': older ? {} : {'next': 'opaque/next+cursor='},
          }),
        );
        await request.response.close();
      });
      final client = Api2Client.connect(
        baseUrl: 'http://${server.address.host}:${server.port}',
        password: 'fixture',
        directory: '/work',
        workspace: 'workspace',
      );
      addTearDown(client.close);
      final gateway = Api2Gateway(client: client);
      final first = await gateway.sessionPage(limit: 2);
      expect(requests, hasLength(1));
      expect(first.items.single.id, 'newest');
      final next = await gateway.sessionPage(cursor: first.nextCursor);
      expect(next.items.single.id, 'older');
      expect(next.hasMore, isFalse);
      expect(requests.first.queryParameters, {
        'directory': '/work',
        'workspace': 'workspace',
        'limit': '2',
        'order': 'desc',
      });
      expect(requests.last.queryParameters, {'cursor': 'opaque/next+cursor='});
    },
  );

  test('v2 opens beyond old history cap with one newest-first page', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final requests = <Uri>[];
    server.listen((request) async {
      requests.add(request.uri);
      final older = request.uri.queryParameters['cursor'] != null;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'data': [
            for (final id
                in older
                    ? ['message-4999', 'message-4998']
                    : ['message-5001', 'message-5000'])
              {'id': id, 'type': 'user', 'text': id},
          ],
          'cursor': older ? {} : {'next': 'next+opaque/token='},
        }),
      );
      await request.response.close();
    });
    final client = Api2Client.connect(
      baseUrl: 'http://${server.address.host}:${server.port}',
      password: 'fixture',
      directory: '/work',
    );
    addTearDown(client.close);
    final api = Api2Gateway(client: client);
    final first = await api.messagePage('session-1', limit: 2);
    expect(requests, hasLength(1));
    expect(first.items.map((message) => message.info.id), [
      'message-5000',
      'message-5001',
    ]);
    final second = await api.messagePage(
      'session-1',
      cursor: first.nextCursor,
      limit: 2,
    );
    expect(second.items.map((message) => message.info.id), [
      'message-4998',
      'message-4999',
    ]);
    expect(second.hasMore, isFalse);
    expect(requests.first.queryParameters, {'limit': '2', 'order': 'desc'});
    expect(requests.last.queryParameters, {'cursor': 'next+opaque/token='});
  });
}
