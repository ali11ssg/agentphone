// AgentPhone sends nothing: no analytics vendor, no crash-reporting vendor,
// no performance tracing, and no advertising permission of any kind.
//
// The upstream project could offer Firebase behind a consent switch. This fork
// removed the vendor completely, so the manifest must carry no vendor
// metadata, no ad permission and no ad-services library, and the Dart code
// must not import a vendor package.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final manifest = File(
    'android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');

  test('the manifest carries no vendor metadata at all', () {
    for (final marker in [
      'firebase_crashlytics_collection_enabled',
      'firebase_analytics_collection_enabled',
      'firebase_performance_collection_deactivated',
      'google_analytics_adid_collection_enabled',
      'google_analytics_ssaid_collection_enabled',
      'google_analytics_automatic_screen_reporting_enabled',
      'google_analytics_default_allow_ad_personalization_signals',
      'google_analytics_default_allow_ad_user_data',
      'google_analytics_default_allow_ad_storage',
    ]) {
      expect(manifest, isNot(contains(marker)), reason: marker);
    }
  });

  test('no advertising permission or ad-services library is requested', () {
    for (final marker in [
      'com.google.android.gms.permission.AD_ID',
      'android.permission.ACCESS_ADSERVICES_AD_ID',
      'android.permission.ACCESS_ADSERVICES_ATTRIBUTION',
      'android.ext.adservices',
    ]) {
      expect(manifest, isNot(contains(marker)), reason: marker);
    }
  });

  test('no Dart file imports a telemetry vendor', () {
    final vendors = [
      'package:firebase_core',
      'package:firebase_analytics',
      'package:firebase_crashlytics',
      'package:firebase_performance',
      'package:google_analytics',
    ];
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final text = entity.readAsStringSync();
      for (final vendor in vendors) {
        if (text.contains("import '$vendor/")) {
          offenders.add('${entity.path}: $vendor');
        }
      }
    }
    expect(offenders, isEmpty);
  });

  test('the app starts the telemetry with the no-op adapter', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('NoOpTelemetryAdapter()'));
    expect(main, isNot(contains('Firebase')));
  });

  test('the privacy policy says nothing is sent', () {
    final policy = File('PRIVACY.md').readAsStringSync();
    expect(policy, contains('**Nothing.**'));
    expect(policy.toLowerCase(), isNot(contains('firebase')));
  });
}
