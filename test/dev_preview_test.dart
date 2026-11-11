import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/domain/dev_preview.dart';

void main() {
  group('DevPreviewLink.parse', () {
    test('takes localhost, 127.0.0.1, 0.0.0.0 and ::1 with a port', () {
      for (final url in const [
        'http://localhost:5173',
        'http://127.0.0.1:5173/',
        'http://0.0.0.0:5173',
        'http://[::1]:5173',
        'HTTP://LOCALHOST:5173',
      ]) {
        final link = DevPreviewLink.parse(url);
        expect(link, isNotNull, reason: url);
        expect(link!.port, 5173, reason: url);
        expect(link.scheme, 'http');
        expect(link.path, '/');
      }
    });

    test('keeps the path and query, and https', () {
      final link = DevPreviewLink.parse('https://localhost:8443/app/x?a=1&b=2');
      expect(link!.scheme, 'https');
      expect(link.path, '/app/x');
      expect(link.query, 'a=1&b=2');
      expect(link.pathAndQuery, '/app/x?a=1&b=2');
    });

    test('leaves every other link alone', () {
      for (final url in const [
        null,
        '',
        'http://example.com:3000',
        'https://localhost.evil.example:3000/',
        'http://localhost',
        'http://localhost:0',
        'http://localhost:70000',
        'ftp://localhost:21',
        'javascript:alert(1)',
        'file:///etc/passwd',
        'http://user:pw@localhost:3000/',
        'http://192.168.1.5:3000',
        'not a url',
      ]) {
        expect(DevPreviewLink.parse(url), isNull, reason: '$url');
      }
    });
  });

  group('scanning conversation text', () {
    test('finds links in prose and drops trailing punctuation', () {
      final links = DevPreviewLink.scan(
        'Local: http://localhost:5173/, also (http://127.0.0.1:3000/a?x=1). '
        'Not this: https://example.com:3000/ or http://localhost.',
      );
      expect(links.map((l) => '${l.port}${l.pathAndQuery}'), [
        '5173/',
        '3000/a?x=1',
      ]);
    });

    test('recent: newest first, one per port, capped', () {
      final links = DevPreviewLink.recent([
        'http://localhost:3000',
        'http://localhost:5173 and http://localhost:3000/new',
        'http://localhost:8080',
      ]);
      expect(links.map((l) => l.port), [8080, 3000, 5173]);
      expect(links[1].path, '/new');
      expect(
        DevPreviewLink.recent([
          for (var p = 4000; p < 4010; p++) 'http://localhost:$p',
        ], limit: 3).map((l) => l.port),
        [4009, 4008, 4007],
      );
    });
  });

  group('DevPreviewTarget.resolve', () {
    const link = DevPreviewLink(port: 5173, path: '/x', query: 'a=1');

    test('the phone is the server: loopback, 0.0.0.0 written as 127.0.0.1', () {
      for (final base in const [
        'http://127.0.0.1:4096',
        'http://localhost:4096',
        'http://[::1]:4096',
      ]) {
        final target = DevPreviewTarget.resolve(link, serverBaseUrl: base);
        expect(target.route, DevPreviewRoute.phone, reason: base);
        expect(target.uri.toString(), 'http://127.0.0.1:5173/x?a=1');
        expect(target.needsAllInterfaces, isFalse);
      }
      final zero = DevPreviewTarget.resolve(
        DevPreviewLink.parse('http://0.0.0.0:3000')!,
        serverBaseUrl: 'http://127.0.0.1:4096',
      );
      expect(zero.uri.toString(), 'http://127.0.0.1:3000/');
    });

    test('a remote server: its host, the link port, with the 0.0.0.0 note', () {
      for (final (base, host) in const [
        ('http://100.64.1.2:4096', '100.64.1.2'),
        ('https://box.tailnet.ts.net', 'box.tailnet.ts.net'),
        ('http://192.168.1.20:4096/api', '192.168.1.20'),
      ]) {
        final target = DevPreviewTarget.resolve(link, serverBaseUrl: base);
        expect(target.route, DevPreviewRoute.remote, reason: base);
        expect(target.uri.toString(), 'http://$host:5173/x?a=1');
        expect(target.host, host);
        expect(target.needsAllInterfaces, isTrue);
      }
    });

    test('the link scheme is kept, not the server scheme', () {
      final target = DevPreviewTarget.resolve(
        const DevPreviewLink(port: 8443, scheme: 'https'),
        serverBaseUrl: 'http://10.0.0.4:4096',
      );
      expect(target.uri.toString(), 'https://10.0.0.4:8443/');
    });

    test('an agent on this phone (a lease to loopback) opens on the phone', () {
      // Claude Code in the in-app Linux: its link is leased, but its address
      // is this phone's loopback, so a localhost link it prints is real.
      final target = DevPreviewTarget.resolve(
        const DevPreviewLink(port: 8080),
        serverBaseUrl: 'ws://127.0.0.1:4099',
        leased: true,
      );
      expect(target.route, DevPreviewRoute.phone);
      expect(target.uri.toString(), 'http://127.0.0.1:8080/');
    });

    test('no server, a private lease, or no host: blocked with a reason', () {
      expect(
        DevPreviewTarget.resolve(link, serverBaseUrl: null).block,
        DevPreviewBlock.noServer,
      );
      expect(
        DevPreviewTarget.resolve(
          link,
          serverBaseUrl: 'http://10.0.0.4:4096',
          leased: true,
        ).block,
        DevPreviewBlock.noServer,
      );
      final noHost = DevPreviewTarget.resolve(link, serverBaseUrl: 'garbage');
      expect(noHost.route, DevPreviewRoute.blocked);
      expect(noHost.block, DevPreviewBlock.noHost);
      expect(noHost.uri, isNull);
    });
  });

  group('devPreviewMayLoad', () {
    final origin = Uri.parse('http://127.0.0.1:5173/');

    test('same host and port only', () {
      expect(
        devPreviewMayLoad(Uri.parse('http://127.0.0.1:5173/a?b'), origin),
        isTrue,
      );
      expect(
        devPreviewMayLoad(Uri.parse('http://127.0.0.1:5174/'), origin),
        isFalse,
      );
      expect(
        devPreviewMayLoad(Uri.parse('http://localhost:5173/'), origin),
        isFalse,
      );
      expect(
        devPreviewMayLoad(Uri.parse('https://example.com/'), origin),
        isFalse,
      );
      expect(
        devPreviewMayLoad(
          Uri.parse('http://127.0.0.1.evil.example:5173/'),
          origin,
        ),
        isFalse,
      );
    });

    test('never a scheme that is not http(s), nor embedded credentials', () {
      for (final url in const [
        'javascript:alert(1)',
        'intent://x#Intent;end',
        'file:///etc/passwd',
        'data:text/html,hi',
        'http://u:p@127.0.0.1:5173/',
      ]) {
        expect(devPreviewMayLoad(Uri.parse(url), origin), isFalse, reason: url);
      }
    });
  });
}
