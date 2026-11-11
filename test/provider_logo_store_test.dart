import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/domain/agent_catalog.dart';
import 'package:agentphone/domain/mark_catalog.dart';
import 'package:agentphone/domain/provider_logo_store.dart';

const String _svg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
    '<path fill="currentColor" d="M2 2h20v20H2z"/></svg>';

ProviderLogoResponse _ok(String body, {String type = 'image/svg+xml'}) =>
    ProviderLogoResponse(
      status: 200,
      contentType: type,
      body: Uint8List.fromList(utf8.encode(body)),
    );

void main() {
  late Directory dir;
  late DateTime clock;
  late List<Uri> requests;
  ProviderLogoResponse? Function(Uri) respond = (_) => _ok(_svg);

  ProviderLogoStore store() => ProviderLogoStore(
    directory: () async => dir,
    now: () => clock,
    // The fallback cases below run with no bundled mark available.
    loadBundled: (_) async => throw StateError('no bundle'),
    fetch: (url) async {
      requests.add(url);
      return respond(url);
    },
  );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('logo_store_test');
    clock = DateTime(2026, 10, 13);
    requests = [];
    respond = (_) => _ok(_svg);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  group('slug', () {
    test('accepts provider ids and lower-cases them', () {
      expect(providerLogoSlug('OpenAI'), 'openai');
      expect(providerLogoSlug('zai-coding-plan'), 'zai-coding-plan');
      expect(providerLogoSlug('302ai'), '302ai');
      expect(providerLogoSlug('a.b_c-d'), 'a.b_c-d');
    });

    test('rejects anything that could change the URL path or host', () {
      for (final bad in [
        '',
        '../etc',
        'a/b',
        'a b',
        'a?x=1',
        'a#x',
        '.hidden',
        'a..b',
        'é',
        'a' * 65,
      ]) {
        expect(providerLogoSlug(bad), isNull, reason: bad);
        expect(providerLogoUrl(bad), isNull, reason: bad);
      }
    });

    test('URL is the fixed models.dev logo path', () {
      expect(
        providerLogoUrl('Anthropic').toString(),
        'https://models.dev/logos/anthropic.svg',
      );
    });
  });

  test(
    'fetches once, then serves memory and disk without the network',
    () async {
      final first = store();
      expect(await first.svgFor('openai'), _svg);
      expect(await first.svgFor('openai'), _svg);
      expect(requests, hasLength(1));
      // A fresh store (a new launch) reads the disk.
      expect(await store().svgFor('openai'), _svg);
      expect(requests, hasLength(1));
    },
  );

  test('concurrent callers share one fetch', () async {
    final s = store();
    final results = await Future.wait([s.svgFor('groq'), s.svgFor('groq')]);
    expect(results, [_svg, _svg]);
    expect(requests, hasLength(1));
  });

  test('refreshes after a week', () async {
    await store().svgFor('openai');
    clock = clock.add(const Duration(days: 8));
    respond = (_) => _ok(_svg.replaceAll('M2', 'M3'));
    final refreshed = File('${dir.path}/openai.svg');
    refreshed.setLastModifiedSync(DateTime(2026, 10, 13));
    expect(await store().svgFor('openai'), contains('M3'));
    expect(requests, hasLength(2));
  });

  test(
    'offline keeps the stale cached logo, and nothing means initials',
    () async {
      await store().svgFor('openai');
      clock = clock.add(const Duration(days: 8));
      respond = (_) => null;
      expect(await store().svgFor('openai'), _svg);
      expect(await store().svgFor('anthropic'), isNull);
    },
  );

  test('a failed fetch is not retried straight away', () async {
    respond = (_) => null;
    final s = store();
    expect(await s.svgFor('groq'), isNull);
    expect(await s.svgFor('groq'), isNull);
    expect(requests, hasLength(1));
  });

  test('rejects oversize, wrong type, non-200 and active content', () async {
    final big = 'x' * (providerLogoMaxBytes + 1);
    final cases = <ProviderLogoResponse>[
      _ok('$_svg<!--$big-->'),
      _ok(_svg, type: 'text/html'),
      _ok('<html></html>'),
      ProviderLogoResponse(
        status: 404,
        contentType: 'image/svg+xml',
        body: Uint8List(0),
      ),
      _ok('<svg><script>alert(1)</script></svg>'),
      _ok('<svg><image href="https://x/y.png"/></svg>'),
    ];
    for (final bad in cases) {
      respond = (_) => bad;
      expect(await store().svgFor('rogue'), isNull);
      expect(File('${dir.path}/rogue.svg').existsSync(), isFalse);
    }
  });

  test('models.dev default sparkle means no logo and is remembered', () async {
    const sparkle = '<svg viewBox="0 0 1 1"><path d="M0 0"/></svg>';
    ProviderLogoStore sparkleStore() => ProviderLogoStore(
      directory: () async => dir,
      now: () => clock,
      defaultLogoMd5: md5.convert(utf8.encode(sparkle)).toString(),
      fetch: (url) async {
        requests.add(url);
        return _ok(sparkle);
      },
    );
    expect(await sparkleStore().svgFor('nobody'), isNull);
    expect(File('${dir.path}/nobody.svg').existsSync(), isFalse);
    // A new launch reads the marker instead of fetching again.
    expect(await sparkleStore().svgFor('nobody'), isNull);
    expect(requests, hasLength(1));
    expect(modelsDevDefaultLogoMd5, hasLength(32));
  });

  test('an unsafe id never reaches the network', () async {
    expect(await store().svgFor('../x'), isNull);
    expect(requests, isEmpty);
  });

  test('a bundled mark is answered without any request', () async {
    final asked = <String>[];
    final bundled = ProviderLogoStore(
      directory: () async => dir,
      loadBundled: (path) async {
        asked.add(path);
        return '<svg/>';
      },
      fetch: (url) async {
        requests.add(url);
        return respond(url);
      },
    );
    expect(await bundled.svgFor('anthropic'), '<svg/>');
    expect(await bundled.svgFor('anthropic'), '<svg/>');
    expect(asked, ['assets/marks/anthropic.svg']);
    expect(requests, isEmpty);
  });

  test('a provider with no bundled mark falls back to the download', () async {
    final unmarked = ProviderLogoStore(
      directory: () async => dir,
      now: () => clock,
      loadBundled: (_) async => throw StateError('never asked'),
      fetch: (url) async {
        requests.add(url);
        return _ok(_svg);
      },
    );
    expect(await unmarked.svgFor('some-new-lab'), _svg);
    expect(requests, hasLength(1));
  });

  test('an unreadable bundled mark falls back to the download', () async {
    final broken = ProviderLogoStore(
      directory: () async => dir,
      now: () => clock,
      loadBundled: (_) async => throw StateError('x'),
      fetch: (url) async {
        requests.add(url);
        return _ok(_svg);
      },
    );
    expect(await broken.svgFor('openai'), _svg);
    expect(requests, hasLength(1));
  });

  test(
    'every listed mark is a bundled single-colour SVG, and none is spare',
    () {
      final files = Directory('assets/marks')
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => n.endsWith('.svg'))
          .map((n) => n.substring(0, n.length - 4))
          .toSet();
      expect(files, bundledMarkSlugs);
      for (final slug in bundledMarkSlugs) {
        final svg = File(markAssetPath(slug)).readAsStringSync();
        expect(svg, contains('currentColor'), reason: slug);
        expect(svg.toLowerCase(), isNot(contains('<image')), reason: slug);
        expect(svg.toLowerCase(), isNot(contains('<script')), reason: slug);
      }
    },
  );

  test('provider ids resolve to a bundled mark, unknown ones to none', () {
    for (final id in [
      'anthropic',
      'openai',
      'google',
      'xai',
      'mistral',
      'deepseek',
      'groq',
      'openrouter',
      'ollama',
      'zai',
      'zhipuai-coding-plan',
      'amazon-bedrock',
      'azure',
      'github-copilot',
      'togetherai',
      'fireworks-ai',
      'cerebras',
      'moonshotai',
      'alibaba',
    ]) {
      expect(bundledMarkSlugs, contains(providerMarkSlug(id)), reason: id);
    }
    expect(providerMarkSlug('some-unknown-gateway'), isNull);
    expect(providerMarkSlug('../etc'), isNull);
  });

  test('every catalog agent with a logo has a bundled mark', () {
    const noLogo = {'fx'};
    for (final agent in AgentCatalog.builtIn.agents) {
      final slug = agentMarkSlug(agent.iconKey);
      if (noLogo.contains(agent.id)) {
        expect(slug, isNull, reason: agent.id);
      } else {
        expect(bundledMarkSlugs, contains(slug), reason: agent.id);
      }
    }
  });
}
