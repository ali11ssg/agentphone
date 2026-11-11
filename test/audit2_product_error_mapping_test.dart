import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/domain/product_repository.dart';
import 'package:agentphone/api2/client.dart';
import 'package:agentphone/api2/gateway_operations.dart';
import 'package:agentphone/api2/transport.dart';
import 'package:agentphone/ui/kit/kit_redact.dart';
import 'package:agentphone/ui/widgets/product_states.dart';

class _ResponseAdapter implements HttpClientAdapter {
  _ResponseAdapter(this.status, this.body);

  final int status;
  final Object body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Synthetic opaque value deliberately lacks recognizable credential syntax.
  const credential = 'syntheticOpaqueCredentialAuditTwo';
  const serverProse = 'Remote explanation';
  const reason = '$serverProse $credential';

  setUp(() {
    KitRedact.clearKnownSecrets();
    KitRedact.registerKnownSecret(credential);
  });
  tearDown(KitRedact.clearKnownSecrets);

  Future<void> verify(
    Future<Object?> Function() action,
    String authoredBody,
  ) async {
    Object? caught;
    try {
      await action();
    } catch (error) {
      caught = error;
    }
    expect(caught is ProductException, isTrue);
    final body = productErrorText(caught!);
    // Boolean assertions never print the captured transport payload on failure.
    expect(body.contains(credential), isFalse, reason: 'body hides secrets');
    expect(body.contains(serverProse), isFalse, reason: 'body is app authored');
    expect(body, authoredBody);
    final details = productErrorDetails(caught);
    expect(details != null, isTrue, reason: 'technical cause is retained');
    expect(details!.contains(credential), isFalse, reason: 'Details redacts');
    expect(details.contains(serverProse), isTrue);
  }

  test(
    'OpenCode 2 operations keep server prose only in redacted Details',
    () async {
      final transport = Api2Transport(
        baseUrl: 'https://server.test',
        password: '',
      );
      transport.dio.httpClientAdapter = _ResponseAdapter(400, {
        '_tag': 'BadRequestError',
        'message': reason,
      });
      addTearDown(transport.close);
      final gateway = Api2OperationsGateway(
        client: Api2Client(transport: transport),
      );
      await verify(
        () => gateway.backgroundSession('session'),
        'Could not background running work',
      );
    },
  );
}
