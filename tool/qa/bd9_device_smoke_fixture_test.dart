import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/api2/gateway.dart';
import 'package:agentphone/api2/gateway_operations.dart';
import 'package:agentphone/diagnostics/perf_trace.dart';

import '../../integration_test/bd9_device_smoke_fixture.dart';

void main() {
  late Bd9DeviceSmokeFixture fixture;

  setUp(() async {
    PerfTrace.logSink = null;
    fixture = await Bd9DeviceSmokeFixture.start();
  });
  tearDown(() => fixture.close());

  test(
    'OpenCode 2 parses health and the global conversation inventory',
    () async {
      final api = Api2Gateway.connect(baseUrl: fixture.baseUrl, password: '');
      addTearDown(api.close);
      expect((await api.health()).healthy, isTrue);
      final sessions = await api.sessions();
      // A folder-local row must not mask a missing global-inventory fetch.
      expect(sessions, isEmpty);
      final repository = Api2OperationsGateway(client: api.client);
      final global = await repository.listGlobalSessions();
      expect(global.items.single.session.id, Bd9DeviceSmokeFixture.sessionID);
      expect(global.items.single.session.title, Bd9DeviceSmokeFixture.title);
      expect(
        global.items.single.projectDirectory,
        Bd9DeviceSmokeFixture.directory,
      );
      expect(fixture.reads, containsAll(['/api/health', '/api/session']));
      expect(fixture.refusedWrites, isEmpty);
    },
  );

  test(
    'fixture refuses model dispatch and records it without response content',
    () async {
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.postUrl(
        Uri.parse('${fixture.baseUrl}/api/session/model/prompt'),
      );
      request.write('{"prompt":"test-only"}');
      final response = await request.close();
      expect(response.statusCode, HttpStatus.methodNotAllowed);
      expect(jsonDecode(await utf8.decoder.bind(response).join()), {
        'error': 'read_only_fixture',
      });
      expect(fixture.refusedWrites, {'/api/session/model/prompt'});
    },
  );

  test(
    'unsupported read paths fail rather than claim fake protocol support',
    () async {
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.getUrl(
        Uri.parse('${fixture.baseUrl}/unknown'),
      );
      final response = await request.close();
      expect(response.statusCode, HttpStatus.notFound);
      await response.drain<void>();
      expect(fixture.unknownReads, {'/unknown'});
    },
  );
}
