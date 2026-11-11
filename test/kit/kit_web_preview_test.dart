import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/l10n/app_localizations.dart';
import 'package:agentphone/ui/kit/kit.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import '../support/fake_webview_platform.dart';
import 'kit_motion_still.dart';

final _origin = Uri.parse('http://127.0.0.1:5173/');

Widget _preview(KitWebPreviewController controller, {bool? supported}) =>
    KitWebPreview(
      origin: _origin,
      controller: controller,
      supported: supported ?? true,
      onLeave: (uri) {},
    );

Widget _app(KitWebPreviewController controller, {bool? supported}) =>
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: KitWebPreview(
          origin: _origin,
          controller: controller,
          supported: supported ?? true,
          onLeave: (uri) {},
        ),
      ),
    );

void main() {
  late FakeWebViewPlatform platform;
  late KitWebPreviewController controller;
  setUp(() {
    platform = FakeWebViewPlatform.install();
    controller = KitWebPreviewController();
  });
  tearDown(() => controller.dispose());

  testWidgets('loads its origin and starts loading', (tester) async {
    await tester.pumpWidget(_app(controller));
    await tester.pump();
    expect(platform.controller!.loaded.single, _origin);
    expect(controller.phase, KitWebPreviewPhase.loading);
    expect(find.byKey(const ValueKey('fake-web-view')), findsOneWidget);
  });

  testWidgets('finishing a page makes it ready and tracks history', (
    tester,
  ) async {
    await tester.pumpWidget(_app(controller));
    await tester.pump();
    platform.controller!.history = true;
    platform.delegate!.onFinished!('http://127.0.0.1:5173/a');
    await tester.pump();
    expect(controller.phase, KitWebPreviewPhase.ready);
    expect(controller.canGoBack, isTrue);
    expect(await controller.goBack(), isTrue);
    expect(platform.controller!.backs, 1);
  });

  testWidgets('goBack says no when the page has no history', (tester) async {
    await tester.pumpWidget(_app(controller));
    await tester.pump();
    expect(await controller.goBack(), isFalse);
    expect(platform.controller!.backs, 0);
  });

  testWidgets('a main-frame failure shows the plain state, Try again reloads', (
    tester,
  ) async {
    await tester.pumpWidget(_app(controller));
    await tester.pump();
    platform.delegate!.onError!(
      const WebResourceError(
        errorCode: -6,
        description: 'net::ERR_CONNECTION_REFUSED',
        isForMainFrame: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nothing is answering yet'), findsOneWidget);
    expect(find.textContaining('Port 5173'), findsOneWidget);
    expect(find.textContaining('ERR_'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('dev-preview-retry')));
    await tester.pump();
    expect(platform.controller!.reloads, 1);
    expect(controller.phase, KitWebPreviewPhase.loading);
  });

  testWidgets('the failure state is not in the tree while the page works', (
    tester,
  ) async {
    await tester.pumpWidget(_app(controller));
    await tester.pump();
    platform.delegate!.onFinished!('http://127.0.0.1:5173/');
    await tester.pumpAndSettle();
    expect(find.text('Nothing is answering yet'), findsNothing);
  });

  testWidgets('without a platform web view it explains and never starts one', (
    tester,
  ) async {
    await tester.pumpWidget(_app(controller, supported: false));
    await tester.pumpAndSettle();
    expect(find.text("Preview isn't available here"), findsOneWidget);
    expect(platform.controller, isNull);
  });

  kitMotionStillTests(
    'KitWebPreview',
    builds: {
      'loading': () => _preview(controller),
      'unavailable': () => _preview(controller, supported: false),
    },
  );
}
