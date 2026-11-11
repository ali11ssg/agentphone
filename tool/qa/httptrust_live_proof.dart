// Real-network proof driver. Input credentials arrive on stdin, never argv.
import 'dart:convert';
import 'dart:io';

import 'package:agentphone/domain/server_trust.dart';

Future<void> main() async {
  final config =
      jsonDecode(await stdin.transform(utf8.decoder).join())
          as Map<String, dynamic>;
  final url = config['url'] as String;
  final action = config['action'] as String;
  HttpClient? client;
  var changed = false;
  try {
    if (action == 'inspect') {
      final certificate = await inspectServerCertificate(url);
      stdout.writeln(
        jsonEncode({'ok': true, 'fingerprint': certificate.fingerprintSha256}),
      );
      return;
    }
    client = createServerHttpClient(
      baseUrl: url,
      cleartextConfirmedOrigin: config['approved'] == true
          ? serverOrigin(url)
          : null,
      certificatePinSha256: config['pin'] as String?,
      onCertificateChanged: () => changed = true,
    );
    final request = await client.getUrl(Uri.parse('$url/api/info'));
    request.followRedirects = false;
    request.persistentConnection = false;
    final username = config['username'] as String;
    final password = config['password'] as String;
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Basic ${base64Encode(utf8.encode('$username:$password'))}',
    );
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    final payload = response.statusCode == 200 ? jsonDecode(body) : null;
    stdout.writeln(
      jsonEncode({
        'ok': response.statusCode == 200 && payload is Map,
        'status': response.statusCode,
        'jsonObject': payload is Map,
        'certificateChanged': changed,
      }),
    );
  } catch (error) {
    // Never retain exception text: an implementation may echo request data.
    stdout.writeln(
      jsonEncode({
        'ok': false,
        'errorType': error.runtimeType.toString(),
        'consentBlocked': error is ServerCleartextConsentException,
        'certificateChanged': changed,
      }),
    );
  } finally {
    client?.close(force: true);
  }
}
