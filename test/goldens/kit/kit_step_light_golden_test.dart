// Gallery for the running step's light and every node state (docs/ux-system/
// kit-api/KitStepTimeline.md "Node states"): a three-step timeline, the step
// under test in the middle with a finished step above and below it, at DPR 3,
// dark and light. The live frames are pumped to exact times of a lap.
//
// Regenerate deliberately:
//   flutter test --update-goldens test/goldens/kit/kit_step_light_golden_test.dart
// and look at every changed image before committing it.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/l10n/app_localizations.dart';
import 'package:agentphone/ui/app_theme.dart';
import 'package:agentphone/ui/kit/chat/kit_step_timeline.dart';
import 'package:agentphone/ui/kit/chat/kit_tool_row.dart';
import 'package:agentphone/ui/kit/kit_motion.dart';

import 'kit_gallery.dart';

const _shot = ValueKey('step-light-shot');

Widget _timeline(
  KitToolStatus status, {
  bool stalled = false,
  bool lastOnly = false,
  bool firstOnly = false,
}) => KitStepTimeline(
  label: 'Ran 3 commands',
  icon: AppIconography.terminal,
  expanded: true,
  stalled: stalled,
  onPressed: () {},
  steps: [
    if (!firstOnly)
      const KitToolRow(
        kind: KitToolKind.read,
        title: 'Read',
        path: 'lib/a.dart',
        status: KitToolStatus.done,
      ),
    KitToolRow(
      kind: KitToolKind.shell,
      title: 'Shell',
      detail: 'flutter test',
      status: status,
    ),
    if (!lastOnly)
      const KitToolRow(
        kind: KitToolKind.edit,
        title: 'Edit',
        path: 'lib/b.dart',
        status: KitToolStatus.done,
      ),
  ],
);

Widget _app(
  Widget child, {
  required bool light,
  bool reduce = false,
  double textScale = 1,
  bool rtl = false,
}) => RepaintBoundary(
  key: _shot,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.forLocale(
      light ? AppTheme.light() : AppTheme.dark(),
      rtl ? const Locale('ar') : const Locale('en'),
    ),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: rtl ? const Locale('ar') : const Locale('en'),
    builder: (context, widget) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        disableAnimations: reduce,
        textScaler: TextScaler.linear(textScale),
      ),
      child: widget!,
    ),
    home: Scaffold(
      body: Padding(padding: const EdgeInsets.all(12), child: child),
    ),
  ),
);

void _size(WidgetTester tester, {double width = 260, double h = 262}) {
  tester.view.physicalSize = Size(width, h) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// The shot at three physical pixels to a dp (the view's own ratio), so the
/// lines of the rail and of the outline can be checked pixel by pixel.
Future<void> _shotOf(WidgetTester tester, String name, bool light) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_shot),
  );
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 3));
  await expectLater(
    image,
    matchesGoldenFile('${name}_${light ? 'light' : 'dark'}.png'),
  );
}

/// ARCH-11: every shot is rendered as Android.
void _test(String name, Future<void> Function(WidgetTester tester) body) =>
    testWidgets(
      name,
      body,
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );

void main() {
  setUpAll(loadKitGalleryFonts);
  tearDown(() => KitMotion.loops = false);

  for (final light in [false, true]) {
    final mode = light ? 'light' : 'dark';

    // The running light at exact times of a lap (2 s).
    for (final t in [0.10, 0.40, 0.55, 0.80]) {
      final pct = (t * 100).round();
      _test('running at $pct% · $mode', (tester) async {
        KitMotion.loops = true;
        _size(tester);
        await tester.pumpWidget(
          _app(_timeline(KitToolStatus.running), light: light),
        );
        await tester.pump();
        await tester.pump(Duration(milliseconds: (t * 2000).round()));
        await _shotOf(tester, 'kit_step_glow_running_t$pct', light);
        await tester.pumpWidget(const SizedBox());
      });
    }

    // Still looks, one per state.
    final still = <String, Widget Function()>{
      'reduced': () => _timeline(KitToolStatus.running),
      'queued': () => _timeline(KitToolStatus.pending),
      'waiting': () => _timeline(KitToolStatus.waitingForYou),
      'done': () => _timeline(KitToolStatus.done),
      'failed': () => _timeline(KitToolStatus.failed),
      'stopped': () => _timeline(KitToolStatus.stopped),
    };
    for (final entry in still.entries) {
      _test('${entry.key} still · $mode', (tester) async {
        KitMotion.loops = false;
        _size(tester);
        await tester.pumpWidget(
          _app(entry.value(), light: light, reduce: entry.key == 'reduced'),
        );
        await tester.pump();
        await _shotOf(tester, 'kit_step_glow_${entry.key}', light);
      });
    }

    // The first and the last step of a group, at 40% of a lap.
    for (final entry in {'first': true, 'last': false}.entries) {
      _test('${entry.key} step at 40% · $mode', (tester) async {
        KitMotion.loops = true;
        _size(tester, h: 214);
        await tester.pumpWidget(
          _app(
            _timeline(
              KitToolStatus.running,
              firstOnly: entry.value,
              lastOnly: !entry.value,
            ),
            light: light,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 800));
        await _shotOf(tester, 'kit_step_glow_${entry.key}_t40', light);
        await tester.pumpWidget(const SizedBox());
      });
    }

    _test('waiting breathes · $mode', (tester) async {
      KitMotion.loops = true;
      _size(tester);
      await tester.pumpWidget(
        _app(_timeline(KitToolStatus.waitingForYou), light: light),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      await _shotOf(tester, 'kit_step_glow_waiting_breathe', light);
      await tester.pumpWidget(const SizedBox());
    });

    _test('background is calmer · $mode', (tester) async {
      KitMotion.loops = true;
      _size(tester);
      await tester.pumpWidget(
        _app(_timeline(KitToolStatus.background), light: light),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1600)); // 40% of 4 s
      await _shotOf(tester, 'kit_step_glow_background_t40', light);
      await tester.pumpWidget(const SizedBox());
    });

    _test('stalled holds the light dimmed · $mode', (tester) async {
      KitMotion.loops = true;
      _size(tester);
      await tester.pumpWidget(
        _app(_timeline(KitToolStatus.running), light: light),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpWidget(
        _app(_timeline(KitToolStatus.running, stalled: true), light: light),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await _shotOf(tester, 'kit_step_glow_stalled', light);
      await tester.pumpWidget(const SizedBox());
    });

    // Changes of state, a moment after the change.
    final changes = <String, (KitToolStatus, int)>{
      'finish_tick': (KitToolStatus.done, 300),
      'finish_spring': (KitToolStatus.done, 700),
      'fail_flash': (KitToolStatus.failed, 100),
      'stop_fade': (KitToolStatus.stopped, 100),
    };
    for (final entry in changes.entries) {
      _test('${entry.key} · $mode', (tester) async {
        KitMotion.loops = true;
        _size(tester);
        await tester.pumpWidget(
          _app(_timeline(KitToolStatus.running), light: light),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 800));
        await tester.pumpWidget(_app(_timeline(entry.value.$1), light: light));
        await tester.pump();
        await tester.pump(Duration(milliseconds: entry.value.$2));
        await _shotOf(tester, 'kit_step_glow_${entry.key}', light);
        await tester.pumpWidget(const SizedBox());
      });
    }

    _test('2.0 text · Arabic · $mode', (tester) async {
      KitMotion.loops = true;
      _size(tester, width: 380, h: 480);
      await tester.pumpWidget(
        _app(
          _timeline(KitToolStatus.running),
          light: light,
          textScale: 2,
          rtl: true,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      await _shotOf(tester, 'kit_step_glow_running_t40_ar_text2', light);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
