import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/l10n/app_localizations.dart';
import 'package:agentphone/ui/app_theme.dart';
import 'package:agentphone/ui/kit/kit.dart';

import 'kit_motion_still.dart';

const _fingerprint =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

void main() {
  Future<void> openMotionHttp(
    BuildContext context, {
    bool privateNetwork = false,
  }) async {
    await showKitServerTrust(
      context,
      origin: 'http://development.example:4098',
      privateNetwork: privateNetwork,
    );
  }

  Future<void> openMotionCertificate(
    BuildContext context, {
    bool certificateChanged = false,
  }) async {
    await showKitServerTrust(
      context,
      origin: 'https://development.example:4099',
      fingerprintSha256: _fingerprint,
      certificateChanged: certificateChanged,
      validFrom: DateTime.utc(2026, 10, 15),
      validTo: DateTime.utc(2027, 10, 15),
    );
  }

  kitMotionStillTests(
    'KitServerTrustBody',
    builds: {
      for (final privateNetwork in [false, true])
        (privateNetwork ? 'private HTTP' : 'public HTTP'): () =>
            SingleChildScrollView(
              child: KitServerTrustBody(
                origin: 'http://development.example:4098',
                privateNetwork: privateNetwork,
              ),
            ),
      for (final certificateChanged in [false, true])
        (certificateChanged
            ? 'changed certificate'
            : 'first certificate'): () => SingleChildScrollView(
          child: KitServerTrustBody(
            origin: 'https://development.example:4099',
            fingerprintSha256: _fingerprint,
            certificateChanged: certificateChanged,
            validFrom: DateTime.utc(2026, 10, 15),
            validTo: DateTime.utc(2027, 10, 15),
          ),
        ),
    },
  );
  kitMotionStillTests(
    'showKitServerTrust',
    opens: {
      for (final privateNetwork in [false, true])
        (privateNetwork ? 'private HTTP' : 'public HTTP'): KitMotionOpen(
          (context) => openMotionHttp(context, privateNetwork: privateNetwork),
          shows: 'http://development.example:4098',
        ),
      for (final certificateChanged in [false, true])
        (certificateChanged
            ? 'changed certificate'
            : 'first certificate'): KitMotionOpen(
          (context) => openMotionCertificate(
            context,
            certificateChanged: certificateChanged,
          ),
          shows: 'https://development.example:4099',
        ),
    },
    changes: {
      'HTTP dismissed': kitModalDismiss(
        openMotionHttp,
        shows: 'http://development.example:4098',
      ),
      'certificate dismissed': kitModalDismiss(
        (context) => openMotionCertificate(context, certificateChanged: true),
        shows: 'https://development.example:4099',
      ),
    },
  );

  for (final private in [true, false]) {
    testWidgets(
      'HTTP ${private ? 'private' : 'public'} warning needs an explicit choice',
      (tester) async {
        bool? result;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async => result = await showKitServerTrust(
                    context,
                    origin: private
                        ? 'http://100.64.0.8:4098'
                        : 'http://public.example:4098',
                    privateNetwork: private,
                  ),
                  child: const Text('Review'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Review'));
        await tester.pumpAndSettle();
        expect(result, isNull);
        expect(
          find.textContaining('password and code travel unencrypted'),
          findsOneWidget,
        );
        expect(find.textContaining('public Wi-Fi'), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(result, isFalse);
        await tester.tap(find.text('Review'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('server-trust-accept')));
        await tester.pumpAndSettle();
        expect(result, isTrue);
      },
    );
  }

  for (final changed in [false, true]) {
    testWidgets(
      'certificate ${changed ? 'replacement' : 'first trust'} displays fingerprint before acceptance',
      (tester) async {
        bool? result;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async => result = await showKitServerTrust(
                    context,
                    origin: 'https://private.example:4099',
                    fingerprintSha256: _fingerprint,
                    certificateChanged: changed,
                    validFrom: DateTime(2026, 10, 1),
                    validTo: DateTime(2027, 10, 1),
                  ),
                  child: const Text('Review'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Review'));
        await tester.pumpAndSettle();
        expect(result, isNull);
        expect(find.textContaining('separate trusted channel'), findsOneWidget);
        expect(find.textContaining('2026'), findsOneWidget);
        expect(find.textContaining('2027'), findsOneWidget);
        final value = tester.widget<KitText>(
          find.byKey(const ValueKey('server-trust-fingerprint')),
        );
        expect(value.text.replaceAll(':', '').toLowerCase(), _fingerprint);
        if (changed) {
          expect(find.text("The server's certificate changed"), findsOneWidget);
          expect(find.text('Trust replacement certificate'), findsOneWidget);
        }
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(result, isFalse);
      },
    );
  }

  testWidgets('Arabic fingerprint stays complete at large text size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ar'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: KitServerTrustBody(
              origin: 'https://private.example:4099',
              fingerprintSha256: _fingerprint,
              certificateChanged: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('server-trust-fingerprint')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
