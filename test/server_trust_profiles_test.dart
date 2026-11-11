import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/state/profiles.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
final _pin = List.filled(32, 'a1').join();

ServerProfile _profile(String url, {String id = 'trust-test'}) =>
    ServerProfile(id: id, name: 'Test server', baseUrl: url);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (_) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  Future<ProfileStore> store() async =>
      ProfileStore(prefs: await SharedPreferences.getInstance());

  test('all remote HTTP origins require an explicit origin-bound choice', () {
    for (final host in [
      '192.168.1.20',
      '100.64.0.1',
      '100.127.255.254',
      'computer.tail123.ts.net',
      'server.example',
      '203.0.113.4',
      '[2001:db8::4]',
    ]) {
      final url = 'http://$host:4098';
      expect(
        validateServerProfileUrl(url, username: 'opencode', password: 'test'),
        isNull,
        reason: url,
      );
      final profile = _profile(url);
      expect(profile.cleartextUnconfirmed, isTrue, reason: url);
      profile.cleartextConfirmedOrigin = cleartextOriginOf(url);
      expect(profile.cleartextUnconfirmed, isFalse, reason: url);
      profile.baseUrl = 'http://$host:4099';
      expect(profile.cleartextUnconfirmed, isTrue, reason: url);
      expect(normalizeServerProfileUrl('$host:4098'), 'https://$host:4098');
    }
  });

  test('invalid server origins cannot carry transport trust', () {
    for (final url in [
      'http://server.example:0',
      'http://server.example:65536',
      'http://server.example:99999999999999999999999',
      'http://server.example:-1',
      'http://server.example:',
      'http://server.example:not-a-port',
      'http://user:secret@server.example',
      'http://@server.example',
      'http://server.example?password=secret',
      'http://server.example?',
      'http://server.example#',
      'http://server.example/path',
      'http://server example',
      'ftp://server.example',
    ]) {
      expect(validateServerProfileUrl(url), isNotNull, reason: url);
      expect(cleartextOriginOf(url), isNull, reason: url);
    }
  });

  test('public HTTP choice survives restart and widget action load', () async {
    final first = await store();
    final profile = _profile('http://server.example:4098')
      ..cleartextConfirmedOrigin = 'http://server.example:4098';
    await first.upsert(profile);
    final restarted = ProfileStore(prefs: first.prefs);
    expect((await restarted.load()).single.cleartextUnconfirmed, isFalse);
    expect(
      (await restarted.loadForWidgetAction(profile.id))!.cleartextUnconfirmed,
      isFalse,
    );
    expect(profile.toJson(), isNot(contains('cleartextConfirmedOrigin')));
    expect(await restarted.removeScopedPreferences(profile.id), isEmpty);
    expect(first.prefs.containsKey('oc.cleartextOk.${profile.id}'), isFalse);
  });

  test(
    'certificate pin survives rebuilding, restart and widget load',
    () async {
      final first = await store();
      final profile = _profile('https://server.example:4098')
        ..certificatePinSha256 = _pin.toUpperCase()
        ..certificatePinOrigin = 'https://server.example:4098';
      await first.upsert(profile);
      final rebuilt = _profile(profile.baseUrl);
      await first.upsert(rebuilt);
      expect(rebuilt.certificatePinSha256, _pin);
      expect(rebuilt.toJson(), isNot(contains('certificatePinSha256')));
      expect(rebuilt.toJson(), isNot(contains('certificatePinOrigin')));
      final restarted = ProfileStore(prefs: first.prefs);
      final restored = (await restarted.load()).single;
      expect(restored.certificatePinSha256, _pin);
      expect(restored.certificatePinOrigin, 'https://server.example:4098');
      final widget = await restarted.loadForWidgetAction(profile.id);
      expect(widget!.certificatePinSha256, _pin);
      expect(widget.certificatePinOrigin, restored.certificatePinOrigin);
      expect(
        restarted.profileScopedPreferenceKeys(profile.id),
        contains('oc.certificatePin.${profile.id}'),
      );
      expect(await restarted.removeScopedPreferences(profile.id), isEmpty);
      expect(
        first.prefs.containsKey('oc.certificatePin.${profile.id}'),
        isFalse,
      );
    },
  );

  test(
    'a different profile does not inherit another profile certificate',
    () async {
      final profiles = await store();
      await profiles.upsert(
        _profile('https://server.example:4098')
          ..certificatePinSha256 = _pin
          ..certificatePinOrigin = 'https://server.example:4098',
      );
      final other = _profile('https://server.example:4098', id: 'other');
      await profiles.upsert(other);
      expect(other.certificatePinSha256, isNull);
      expect(other.certificatePinOrigin, isNull);
    },
  );

  test('changing host, port or scheme removes the certificate pin', () async {
    for (final changed in [
      'https://other.example:4098',
      'https://server.example:4099',
      'http://server.example:4098',
    ]) {
      final profiles = await store();
      final profile = _profile('https://server.example:4098')
        ..certificatePinSha256 = _pin
        ..certificatePinOrigin = 'https://server.example:4098';
      await profiles.upsert(profile);
      profile.baseUrl = changed;
      await profiles.upsert(profile);
      expect(profile.certificatePinSha256, isNull, reason: changed);
      expect(profile.certificatePinOrigin, isNull, reason: changed);
      expect(
        profiles.prefs.containsKey('oc.certificatePin.${profile.id}'),
        isFalse,
      );
    }
  });

  test('malformed explicit pins fail before saving metadata', () async {
    for (final pin in ['', 'a1', '${_pin}00', List.filled(64, 'z').join()]) {
      final profiles = await store();
      final profile = _profile('https://server.example:4098')
        ..certificatePinSha256 = pin
        ..certificatePinOrigin = 'https://server.example:4098';
      await expectLater(profiles.upsert(profile), throwsArgumentError);
      expect(profiles.prefs.containsKey('oc.profiles'), isFalse);
    }
  });

  test(
    'malformed and wrong-origin persisted pins never restore trust',
    () async {
      final profiles = await store();
      final profile = _profile('https://server.example:4098');
      await profiles.upsert(profile);
      for (final stored in [
        '{invalid json',
        jsonEncode({'origin': 'https://server.example:4098', 'sha256': 'bad'}),
        jsonEncode({'origin': 'https://other.example:4098', 'sha256': _pin}),
        jsonEncode({'origin': 'http://server.example:4098', 'sha256': _pin}),
        jsonEncode({
          'origin': 'https://server.example:4098/path',
          'sha256': _pin,
        }),
      ]) {
        await profiles.prefs.setString(
          'oc.certificatePin.${profile.id}',
          stored,
        );
        final restored = (await ProfileStore(
          prefs: profiles.prefs,
        ).load()).single;
        expect(restored.certificatePinSha256, isNull);
        expect(restored.certificatePinOrigin, isNull);
        final widget = await profiles.loadForWidgetAction(profile.id);
        expect(widget!.certificatePinSha256, isNull);
      }
    },
  );
}
