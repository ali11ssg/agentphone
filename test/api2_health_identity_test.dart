import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/api2/gateway.dart';
import 'package:agentphone/domain/models.dart';

class _HealthAdapter implements HttpClientAdapter {
  _HealthAdapter(this.body, this.contentType);
  final String body;
  final String contentType;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    body,
    200,
    headers: {
      Headers.contentTypeHeader: [contentType],
    },
  );

  @override
  void close({bool force = false}) {}
}

void main() {
  for (final response in [
    ('{"healthy":true}', 'application/json'),
    ('{"healthy":true,"version":"1.19.0"}', 'application/json'),
    ('<!doctype html><html>Server UI</html>', 'text/html'),
  ]) {
    test(
      'unsupported health shape triggers connection redetection: $response',
      () async {
        final gateway = Api2Gateway.connect(
          baseUrl: 'http://localhost:4097',
          password: '',
        );
        gateway.transport.dio.httpClientAdapter = _HealthAdapter(
          response.$1,
          response.$2,
        );
        addTearDown(gateway.close);
        await expectLater(
          gateway.health(),
          throwsA(
            isA<ApiException>().having(
              (error) => error.errorTag,
              'redetection signal',
              unexpectedHealthShapeTag,
            ),
          ),
        );
      },
    );
  }
}
