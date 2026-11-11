// Golden render of the bundled provider marks in a provider list, the way
// the model picker and Providers screen draw them: every common provider
// wears its own single-colour mark offline, an unknown one shows initials.
//
// Regenerate deliberately:
//   flutter test --update-goldens test/goldens/provider_marks_golden_test.dart
// and look at every changed image before committing it.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/domain/provider_logo_store.dart';
import 'package:agentphone/ui/app_theme.dart';
import 'package:agentphone/ui/kit/kit.dart';
import 'package:agentphone/ui/widgets/provider_logo.dart';

import '../../tool/capture/fixtures.dart' show loadCaptureFonts;

const _providers = [
  ('anthropic', 'Anthropic'),
  ('openai', 'OpenAI'),
  ('google', 'Google'),
  ('xai', 'xAI'),
  ('mistral', 'Mistral'),
  ('deepseek', 'DeepSeek'),
  ('groq', 'Groq'),
  ('openrouter', 'OpenRouter'),
  ('ollama', 'Ollama'),
  ('alibaba', 'Alibaba'),
  ('moonshotai', 'Moonshot AI'),
  ('zai-coding-plan', 'Z.AI Coding Plan'),
  ('amazon-bedrock', 'Amazon Bedrock'),
  ('azure', 'Azure'),
  ('github-copilot', 'GitHub Copilot'),
  ('togetherai', 'Together AI'),
  ('fireworks-ai', 'Fireworks AI'),
  ('cerebras', 'Cerebras'),
  ('some-new-lab', 'Some new lab'),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadCaptureFonts);

  for (final light in [false, true]) {
    final mode = light ? 'light' : 'dark';
    testWidgets('provider marks · $mode', (tester) async {
      tester.view.physicalSize = const Size(412, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      debugDefaultTargetPlatformOverride = TargetPlatform.android; // ARCH-11
      final boundary = GlobalKey();
      // A store per test: the shared one keeps its futures across the fake
      // clocks of separate tests.
      final store = ProviderLogoStore(
        loadBundled: (path) => File(path).readAsString(),
        fetch: (_) async => null,
        directory: () async => null,
      );
      ProviderLogo.logoLoaderOverride = store.svgFor;
      addTearDown(() => ProviderLogo.logoLoaderOverride = null);
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: light ? AppTheme.light() : AppTheme.dark(),
            home: Scaffold(
              body: ListView(
                children: [
                  for (final (id, name) in _providers)
                    KitRow(
                      key: ValueKey('provider-$id'),
                      title: name,
                      leading: ProviderLogo(id),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      // The bundle read and the SVG parse are real I/O, outside the fake
      // clock: alternate real waits with frames until the marks are drawn.
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)),
        );
        await tester.pump(const Duration(milliseconds: 200));
      }
      await tester.pumpAndSettle();
      for (final (id, _) in _providers) {
        expect(
          find.descendant(
            of: find.byKey(ValueKey('provider-$id')),
            matching: find.byType(SvgPicture),
          ),
          id == 'some-new-lab' ? findsNothing : findsOneWidget,
          reason: id,
        );
      }
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(boundary),
        matchesGoldenFile('providers_marks_list_$mode.png'),
      );
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
