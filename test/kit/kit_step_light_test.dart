// The light on a step's node (docs/ux-system/kit-api/KitStepTimeline.md "Node
// states"): the phases of one lap, the split's symmetry and merge point, one
// look per state, reduced motion, and no ticker or timer left behind.
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/l10n/app_localizations.dart';
import 'package:agentphone/ui/app_theme.dart';
import 'package:agentphone/ui/kit/chat/kit_step_timeline.dart';
import 'package:agentphone/ui/kit/chat/kit_tool_row.dart';
import 'package:agentphone/ui/kit/kit_motion.dart';
import 'package:agentphone/ui/kit/kit_status_mark.dart';

Widget _app(Widget child, {bool reduce = false}) => MaterialApp(
  theme: AppTheme.dark(),
  themeAnimationDuration: Duration.zero,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, widget) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
    child: widget!,
  ),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

Widget _timeline(
  KitToolStatus status, {
  DateTime? startedAt,
  bool stalled = false,
  int running = 1,
}) => KitStepTimeline(
  label: 'Ran commands',
  icon: AppIconography.tools,
  expanded: true,
  stalled: stalled,
  onPressed: () {},
  steps: [
    const KitToolRow(
      kind: KitToolKind.read,
      title: 'Read',
      status: KitToolStatus.done,
    ),
    for (var i = 0; i < running; i++)
      KitToolRow(
        kind: KitToolKind.shell,
        title: 'Shell',
        status: status,
        startedAt: startedAt,
      ),
    const KitToolRow(
      kind: KitToolKind.edit,
      title: 'Edit',
      status: KitToolStatus.done,
    ),
  ],
);

Finder get _light => find.byKey(const ValueKey('kit-step-light'));
Finder get _tick => find.byKey(const ValueKey('kit-step-tick'));
Finder get _glyph => find.byIcon(AppIconography.terminal);

RenderObject _canvas(WidgetTester tester) => tester.renderObject(_light.first);

/// Starts the lap, then moves it to [ms] into the lap.
Future<void> _at(WidgetTester tester, Widget w, int ms) async {
  await tester.pumpWidget(_app(w));
  await tester.pump();
  await tester.pump(Duration(milliseconds: ms));
}

void main() {
  tearDown(() => KitMotion.loops = false);

  group('one lap of 2 s', () {
    testWidgets('0-28%: one light from above, no outline yet', (tester) async {
      KitMotion.loops = true;
      await _at(tester, _timeline(KitToolStatus.running), 200);
      expect(_canvas(tester), paints..line());
      expect(_canvas(tester), isNot(paints..path()));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('26-66%: both halves fill at once, with a head each', (
      tester,
    ) async {
      KitMotion.loops = true;
      await _at(tester, _timeline(KitToolStatus.running), 800);
      // Two fills and two heads, no light on the rail.
      expect(
        _canvas(tester),
        paints
          ..path()
          ..path()
          ..path()
          ..path(),
      );
      expect(_canvas(tester), isNot(paints..line()));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('64-95%: one light goes on down the rail, the outline dims', (
      tester,
    ) async {
      KitMotion.loops = true;
      await _at(tester, _timeline(KitToolStatus.running), 1500);
      expect(
        _canvas(tester),
        paints
          ..path()
          ..path()
          ..line(),
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the lap repeats: 95-100% is quiet, then it starts again', (
      tester,
    ) async {
      KitMotion.loops = true;
      await _at(tester, _timeline(KitToolStatus.running), 1980);
      expect(_canvas(tester), isNot(paints..line()));
      await tester.pump(const Duration(milliseconds: 220));
      expect(_canvas(tester), paints..line());
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a background process runs a calmer 4 s lap', (tester) async {
      KitMotion.loops = true;
      // 40% of 4 s: filling. A 2 s lap would be back at its start.
      await _at(tester, _timeline(KitToolStatus.background), 1600);
      expect(
        _canvas(tester),
        paints
          ..path()
          ..path(),
      );
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('the split', () {
    test('the halves mirror each other and meet at the bottom centre', () {
      for (final stroke in [1.8, 2.6]) {
        final l = debugStepOutlineHalf(20, stroke, left: true);
        final r = debugStepOutlineHalf(20, stroke, left: false);
        final lm = l.computeMetrics().single;
        final rm = r.computeMetrics().single;
        expect(lm.length, closeTo(rm.length, 1e-4));
        // Start at the top centre, end at the bottom centre, inside the edge.
        final top = Offset(10, stroke / 2);
        final bottom = Offset(10, 20 - stroke / 2);
        for (final m in [lm, rm]) {
          expect(
            (m.getTangentForOffset(0)!.position - top).distance,
            lessThan(1e-4),
          );
          expect(
            (m.getTangentForOffset(m.length)!.position - bottom).distance,
            lessThan(1e-4),
          );
        }
        final lb = l.getBounds();
        final rb = r.getBounds();
        expect(lb.left, closeTo(20 - rb.right, 1e-4));
        expect(lb.right, closeTo(10, 1e-4));
        expect(lb.top, closeTo(rb.top, 1e-4));
        // Inside the tile: the stroke never grows the node.
        expect(lb.left, closeTo(stroke / 2, 1e-4));
      }
    });
  });

  group('states', () {
    testWidgets('running keeps its glyph; no spinner or status mark', (
      tester,
    ) async {
      KitMotion.loops = true;
      await _at(tester, _timeline(KitToolStatus.running), 400);
      expect(_glyph, findsOneWidget);
      expect(_light, findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(KitStatusMark), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('queued: a dim outline, nothing moves', (tester) async {
      KitMotion.loops = true;
      await tester.pumpWidget(_app(_timeline(KitToolStatus.pending)));
      await tester.pump();
      expect(_light, findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'waiting holds a filled outline and breathes; still when reduced',
      (tester) async {
        KitMotion.loops = true;
        await tester.pumpWidget(_app(_timeline(KitToolStatus.waitingForYou)));
        await tester.pump();
        expect(_light, findsOneWidget);
        expect(find.byType(KitStatusMark), findsNothing);
        expect(tester.hasRunningAnimations, isTrue);
        await tester.pumpWidget(
          _app(_timeline(KitToolStatus.waitingForYou), reduce: true),
        );
        await tester.pump();
        expect(_light, findsOneWidget);
        expect(tester.hasRunningAnimations, isFalse);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('finishing flashes the tick, then the glyph springs back', (
      tester,
    ) async {
      KitMotion.loops = true;
      await _at(tester, _timeline(KitToolStatus.running), 300);
      await tester.pumpWidget(_app(_timeline(KitToolStatus.done)));
      await tester.pump(const Duration(milliseconds: 50));
      expect(_light, findsNothing);
      expect(_tick, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));
      expect(_tick, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200));
      expect(_tick, findsNothing);
      expect(_glyph, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('a step that was never running gets no tick', (tester) async {
      KitMotion.loops = true;
      await tester.pumpWidget(_app(_timeline(KitToolStatus.pending)));
      await tester.pumpWidget(_app(_timeline(KitToolStatus.done)));
      await tester.pump(const Duration(milliseconds: 50));
      expect(_tick, findsNothing);
      expect(_glyph, findsOneWidget);
    });

    testWidgets(
      'failing flashes the danger outline once, then the failed mark',
      (tester) async {
        KitMotion.loops = true;
        await _at(tester, _timeline(KitToolStatus.running), 300);
        await tester.pumpWidget(_app(_timeline(KitToolStatus.failed)));
        await tester.pump(const Duration(milliseconds: 100));
        expect(_light, findsOneWidget);
        expect(find.byType(KitStatusMark), findsNothing);
        await tester.pump(const Duration(milliseconds: 400));
        expect(_light, findsNothing);
        expect(find.byType(KitStatusMark), findsOneWidget);
      },
    );

    testWidgets('stopping fades the light out, no tick, the glyph stays', (
      tester,
    ) async {
      KitMotion.loops = true;
      await _at(tester, _timeline(KitToolStatus.running), 300);
      await tester.pumpWidget(_app(_timeline(KitToolStatus.stopped)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_light, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200));
      expect(_light, findsNothing);
      expect(_tick, findsNothing);
      expect(_glyph, findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('connection lost holds the light; it goes on when back', (
      tester,
    ) async {
      KitMotion.loops = true;
      await _at(tester, _timeline(KitToolStatus.running), 800);
      await tester.pumpWidget(
        _app(_timeline(KitToolStatus.running, stalled: true)),
      );
      await tester.pump();
      expect(_light, findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
      await tester.pumpWidget(_app(_timeline(KitToolStatus.running)));
      await tester.pump();
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('steps in parallel each run their own light', (tester) async {
      KitMotion.loops = true;
      await tester.pumpWidget(
        _app(_timeline(KitToolStatus.running, running: 2)),
      );
      await tester.pump();
      expect(_light, findsNWidgets(2));
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('reduced motion: a still filled outline, no moving controller', (
    tester,
  ) async {
    KitMotion.loops = true;
    await tester.pumpWidget(
      _app(_timeline(KitToolStatus.running), reduce: true),
    );
    await tester.pump();
    expect(_light, findsOneWidget);
    expect(
      _canvas(tester),
      paints
        ..path()
        ..path(),
    );
    expect(_glyph, findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('the counter ticks by the second and leaves no timer behind', (
    tester,
  ) async {
    final started = clock.now().subtract(const Duration(seconds: 12));
    await tester.pumpWidget(
      _app(_timeline(KitToolStatus.running, startedAt: started)),
    );
    expect(find.text('12 s'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('14 s'), findsOneWidget);
    await tester.pump(const Duration(seconds: 51));
    expect(find.text('1 min 5 s'), findsOneWidget);
    await tester.pumpWidget(_app(_timeline(KitToolStatus.done)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('kit-step-counter')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('no ticker is left after the node is disposed mid-lap', (
    tester,
  ) async {
    KitMotion.loops = true;
    await _at(tester, _timeline(KitToolStatus.running), 700);
    await tester.pumpWidget(const SizedBox());
    expect(tester.binding.transientCallbackCount, 0);
  });
}
