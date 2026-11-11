// KitLogPanel with `searchable`: search with the matches marked, stepping
// between them, Pause and Follow, selection, at large text and right to left.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/l10n/app_localizations.dart';
import 'package:agentphone/ui/app_theme.dart';
import 'package:agentphone/ui/kit/kit_log_panel.dart';

const _search = ValueKey('kit-log-search');
const _prev = ValueKey('kit-log-prev');
const _next = ValueKey('kit-log-next');
const _pause = ValueKey('kit-log-pause');

Future<void> _host(
  WidgetTester tester,
  KitLogBuffer lines, {
  double textScale = 1,
  Locale locale = const Locale('en'),
  bool searchable = true,
  bool follow = true,
}) async {
  tester.view
    ..physicalSize = const Size(412, 915)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: KitLogPanel(
            lines: lines,
            size: KitLogSize.fill,
            searchable: searchable,
            follow: follow,
            wrap: false,
            live: true,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

KitLogBuffer _log({int count = 200}) {
  final buffer = KitLogBuffer();
  for (var i = 0; i < count; i++) {
    buffer.add(
      KitLogLine(
        i == 10
            ? 'line $i compiled with ERROR in src/a.ts'
            : i == 150
            ? 'line $i another error here'
            : 'line $i ok',
      ),
    );
  }
  return buffer;
}

ScrollPosition _vertical(WidgetTester tester) => tester
    .stateList<ScrollableState>(find.byType(Scrollable))
    .firstWhere((s) => s.axisDirection == AxisDirection.down)
    .position;

double _offset(WidgetTester tester) => _vertical(tester).pixels;

double _max(WidgetTester tester) => _vertical(tester).maxScrollExtent;

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(_search), text);
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump();
}

/// The background-filled spans drawn in any line.
List<String> _marked(WidgetTester tester) {
  final out = <String>[];
  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    rich.text.visitChildren((span) {
      if (span is TextSpan &&
          span.style?.backgroundColor != null &&
          span.text != null) {
        out.add(span.text!);
      }
      return true;
    });
  }
  return out;
}

void main() {
  testWidgets('a plain panel has no search tools', (tester) async {
    await _host(tester, _log(count: 5), searchable: false);
    expect(find.byKey(_search), findsNothing);
    expect(find.byKey(_pause), findsNothing);
  });

  testWidgets('searching counts matches, marks them and shows the newest', (
    tester,
  ) async {
    await _host(tester, _log());
    expect(find.byKey(_search), findsOneWidget);
    await _type(tester, 'error');
    expect(find.text('2 results'), findsOneWidget);
    expect(find.textContaining('line 150', findRichText: true), findsOneWidget);
    expect(_marked(tester), ['error']);
    expect(find.byKey(_prev), findsOneWidget);
    expect(find.byKey(_next), findsOneWidget);
  });

  testWidgets('matching ignores case and Previous steps to the older match', (
    tester,
  ) async {
    await _host(tester, _log());
    await _type(tester, 'ERROR');
    expect(_marked(tester), ['error']);
    await tester.tap(find.byKey(_prev));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(
      find.textContaining('line 10 compiled', findRichText: true),
      findsOneWidget,
    );
    expect(_marked(tester), contains('ERROR'));
    await tester.tap(find.byKey(_next));
    await tester.pump();
    await tester.pump();
    expect(
      find.textContaining('line 150 another', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('no match says so and marks nothing', (tester) async {
    await _host(tester, _log(count: 20));
    await _type(tester, 'zzz');
    expect(find.text('No results'), findsOneWidget);
    expect(_marked(tester), isEmpty);
    expect(find.byKey(_prev), findsNothing);
  });

  testWidgets('clearing the search clears the marks', (tester) async {
    await _host(tester, _log());
    await _type(tester, 'error');
    expect(_marked(tester), isNotEmpty);
    await _type(tester, '');
    expect(_marked(tester), isEmpty);
  });

  testWidgets('new lines that match are found while the log grows', (
    tester,
  ) async {
    final lines = _log(count: 20);
    await _host(tester, lines);
    await _type(tester, 'boom');
    expect(find.text('No results'), findsOneWidget);
    lines.add(const KitLogLine('boom: it fell over'));
    await tester.pump();
    await tester.pump();
    expect(find.text('1 result'), findsOneWidget);
  });

  testWidgets('Pause stops the scroll, Follow returns to the newest line', (
    tester,
  ) async {
    final lines = _log(count: 120);
    await _host(tester, lines);
    await tester.pump();
    expect(_offset(tester), closeTo(_max(tester), 1));
    await tester.tap(find.byKey(_pause));
    await tester.pump();
    expect(find.byTooltip('Follow new output'), findsOneWidget);
    final before = _offset(tester);
    for (var i = 0; i < 40; i++) {
      lines.add(KitLogLine('late $i'));
    }
    await tester.pump();
    await tester.pump();
    expect(_offset(tester), before, reason: 'paused: the view stays put');
    expect(_max(tester), greaterThan(before + 100));
    await tester.tap(find.byKey(_pause));
    await tester.pumpAndSettle();
    expect(_offset(tester), closeTo(_max(tester), 2));
    expect(find.byTooltip('Pause following'), findsOneWidget);
  });

  testWidgets('without Pause new lines are followed', (tester) async {
    final lines = _log(count: 120);
    await _host(tester, lines);
    for (var i = 0; i < 40; i++) {
      lines.add(KitLogLine('late $i'));
    }
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(_offset(tester), closeTo(_max(tester), 2));
  });

  testWidgets('lines can be selected and copied on a phone', (tester) async {
    await _host(tester, _log(count: 5));
    expect(find.byType(SelectionArea), findsOneWidget);
  });

  testWidgets('copy all copies the lines, not the marks', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _host(tester, _log(count: 3));
    await _type(tester, 'ok');
    await tester.tap(find.byKey(const ValueKey('kit-log-copy-all')));
    await tester.pump();
    expect(copied.single, 'line 0 ok\nline 1 ok\nline 2 ok');
  });

  testWidgets('at 2.5x text the tools fit and search still works', (
    tester,
  ) async {
    await _host(tester, _log(), textScale: 2.5);
    expect(tester.takeException(), isNull);
    expect(find.byKey(_pause), findsOneWidget);
    await _type(tester, 'error');
    expect(tester.takeException(), isNull);
    expect(find.text('2 results'), findsOneWidget);
    expect(find.byKey(_next), findsOneWidget);
  });

  testWidgets('right to left keeps the log left to right and the tools whole', (
    tester,
  ) async {
    await _host(tester, _log(), locale: const Locale('ar'));
    expect(tester.takeException(), isNull);
    await _type(tester, 'error');
    expect(tester.takeException(), isNull);
    final line = find.textContaining('line 150', findRichText: true);
    expect(line, findsOneWidget);
    final direction = tester.widget<RichText>(
      find
              .descendant(of: line.first, matching: find.byType(RichText))
              .evaluate()
              .isEmpty
          ? line.first
          : find
                .descendant(of: line.first, matching: find.byType(RichText))
                .first,
    );
    expect(direction.textDirection, TextDirection.ltr);
    expect(find.byKey(_pause), findsOneWidget);
  });
}
