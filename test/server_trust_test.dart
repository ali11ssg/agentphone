import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/domain/server_trust.dart';

void main() {
  test('trust origin includes the effective port and ignores the API path', () {
    expect(serverOrigin('http://EXAMPLE.com/api'), 'http://example.com:80');
    expect(serverOrigin('https://example.com:443/'), 'https://example.com:443');
    expect(serverOrigin('http://[::1]:4098'), 'http://[::1]:4098');
  });

  test('rejects credentials, query, fragment, and non-HTTP server URLs', () {
    for (final url in [
      'https://user:password@example.com',
      'https://example.com?token=secret',
      'https://example.com#secret',
      'file:///tmp/socket',
      'wss://example.com',
      'http://',
    ]) {
      expect(() => serverOrigin(url), throwsFormatException);
    }
  });

  test(
    'loopback works without consent, all remote HTTP needs its own choice',
    () {
      for (final host in ['127.0.0.1', 'localhost', '[::1]']) {
        expect(isCleartextChoiceRequired('http://$host:4098'), isFalse);
        validateServerTrust(baseUrl: 'http://$host:4098');
      }
      for (final host in [
        '192.168.1.2',
        '100.64.0.2',
        'machine.tail.ts.net',
        '203.0.113.2',
        'example.com',
      ]) {
        final url = 'http://$host:4098';
        expect(isCleartextChoiceRequired(url), isTrue);
        expect(
          () => validateServerTrust(baseUrl: url),
          throwsA(isA<ServerCleartextConsentException>()),
        );
        validateServerTrust(
          baseUrl: url,
          cleartextConfirmedOrigin: serverOrigin(url),
        );
        expect(
          () => validateServerTrust(
            baseUrl: url,
            cleartextConfirmedOrigin: 'http://$host:4099',
          ),
          throwsA(isA<ServerCleartextConsentException>()),
        );
      }
    },
  );

  test('a certificate pin cannot be downgraded to HTTP', () {
    expect(
      () => validateServerTrust(
        baseUrl: 'http://localhost:4098',
        certificatePinSha256: 'a' * 64,
      ),
      throwsFormatException,
    );
  });

  test('SHA-256 pin is complete and permits colon display formatting', () {
    expect(
      normalizeCertificateFingerprint(List.filled(32, 'AB').join(':')),
      'ab' * 32,
    );
    for (final value in ['', 'abc', 'g' * 64, 'a' * 63, 'a' * 65]) {
      expect(
        () => normalizeCertificateFingerprint(value),
        throwsFormatException,
      );
    }
  });
}
