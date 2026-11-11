// Phone-check recovery and download progress at 412 x 915, including Arabic.
//
// Regenerate deliberately:
//   flutter test --update-goldens test/goldens/agents_phone_check_golden_test.dart
// and look at every changed image before committing it.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/domain/agent_catalog.dart';
import 'package:agentphone/domain/phone_agent_host.dart';
import 'package:agentphone/domain/phone_agents_source.dart';
import 'package:agentphone/l10n/app_localizations.dart';
import 'package:agentphone/ui/app_theme.dart';
import 'package:agentphone/ui/screens/agents/agent_sheet.dart';
import 'package:agentphone/ui/screens/chats/chats_host.dart';

import '../../tool/capture/fixtures.dart' show captureTheme;
import '../support/agents_fakes.dart';
import '../support/chats_fakes.dart';
import 'kit/kit_gallery.dart' show loadKitGalleryFonts;

class _Phone extends FakePhoneAgentsSource implements PhoneAgentRecoverySource {
  _Phone({this.downloading = false})
    : super(rows: [agentRowFor('claude', FakeAgentStage.needsCheck)]);
  final bool downloading;
  @override
  Future<AgentPhoneCheckResult> runAgentPhoneCheck(String agentId) =>
      downloading
      ? Completer<AgentPhoneCheckResult>().future
      : super.runAgentPhoneCheck(agentId);
  @override
  Future<AgentPhoneCheckResult> usePreviousAgentVersion(String agentId) =>
      super.runAgentPhoneCheck(agentId);
}

// Flutter's test renderer has no Android system font fallback. Button themes
// carry their own AppSans styles, so loading Noto alone is insufficient. Match
// the established account/kit golden harness by explicitly attaching Noto to
// those styles; the real phone supplies this fallback through the platform.
ThemeData _theme(Locale locale) {
  final theme = AppTheme.forLocale(captureTheme(light: true), locale);
  if (locale.languageCode != 'ar') return theme;
  ButtonStyle? withFallback(ButtonStyle? style) {
    final text = style?.textStyle;
    if (style == null || text == null) return style;
    return style.copyWith(
      textStyle: WidgetStateProperty.resolveWith(
        (states) => text
            .resolve(states)
            ?.copyWith(fontFamilyFallback: const ['Noto Sans Arabic']),
      ),
    );
  }

  return theme.copyWith(
    filledButtonTheme: FilledButtonThemeData(
      style: withFallback(theme.filledButtonTheme.style),
    ),
    textButtonTheme: TextButtonThemeData(
      style: withFallback(theme.textButtonTheme.style),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: withFallback(theme.outlinedButtonTheme.style),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: withFallback(theme.elevatedButtonTheme.style),
    ),
  );
}

void main() {
  setUpAll(loadKitGalleryFonts);
  for (final scene in ['download', 'helper', 'signin', 'rollback_ar']) {
    testWidgets('phone check $scene', (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final locale = Locale(scene == 'rollback_ar' ? 'ar' : 'en');
      final boundary = GlobalKey();
      final agents = _Phone(downloading: scene == 'download')
        ..progress = const AgentSetupProgress(
          agentId: 'claude',
          phase: AgentSetupPhase.installing,
          componentId: 'agent-claude',
          downloadedBytes: 60000000,
          totalBytes: 240000000,
          checkStep: AgentPhoneCheckStep.install,
        )
        ..nextCheck = AgentPhoneCheckResult(
          agentId: 'claude',
          architecture: AgentArchitecture.arm64,
          passed: false,
          completed: const [
            AgentPhoneCheckStep.install,
            AgentPhoneCheckStep.version,
            AgentPhoneCheckStep.daemon,
          ],
          failure: scene == 'signin'
              ? AgentHostFailure.needsSignIn
              : AgentHostFailure.helperVersion,
          previousVersion: scene == 'rollback_ar' ? '2.1.283' : null,
          details: 'Paseo expected 0.11.2; observed 0.9.2',
        );
      final host = FakeChatsHost(FakeChatFeedSource())..phoneAgents = agents;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatsHostProvider.overrideWithValue(host)],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: _theme(locale),
            locale: locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: RepaintBoundary(
              key: boundary,
              child: const Material(
                child: AgentSheet(
                  agentId: 'claude',
                  step: AgentSheetStep.check,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      if (scene != 'download') {
        await tester.pumpAndSettle();
        if (scene == 'helper') {
          await tester.tap(find.byKey(const ValueKey('agents-check-details')));
          await tester.pumpAndSettle();
        }
      } else {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(boundary),
        matchesGoldenFile('agents_phone_check_${scene}_light.png'),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }
}
