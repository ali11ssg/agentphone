import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/l10n/app_localizations.dart';
import 'package:agentphone/state/managed_move.dart';
import 'package:agentphone/ui/app_theme.dart';
import 'package:agentphone/ui/widgets/managed_move_view.dart';

Widget _app(Widget home) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: AppTheme.dark(),
  home: home,
);

void main() {
  group('the move page, shown the way the app shows it on first launch', () {
    Future<void> pumpView(WidgetTester tester, ManagedMoveAttempt? failure) =>
        tester.pumpWidget(
          _app(ManagedMoveView(failure: failure, onTryAgain: () {})),
        );

    void expectThemed(WidgetTester tester, String text) {
      final finder = find.text(text);
      expect(finder, findsOneWidget);
      // No Material above the words means Flutter's fallback text style:
      // yellow double underline, as seen on the owner's phone.
      expect(
        find.ancestor(of: finder, matching: find.byType(Material)),
        findsWidgets,
      );
      final style = DefaultTextStyle.of(tester.element(finder)).style;
      expect(style.decoration, isNot(TextDecoration.underline));
      expect(style.decorationStyle, isNot(TextDecorationStyle.double));
    }

    testWidgets('failure is themed, says why, folds the technical text', (
      tester,
    ) async {
      await pumpView(
        tester,
        const ManagedMoveAttempt.failure(
          ManagedMoveReason.moveStopped,
          details: 'exit 74 ENOSPC',
        ),
      );
      await tester.pump();
      expectThemed(tester, 'Could not finish');
      expect(find.textContaining('low on free space'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      // The raw text is not main copy.
      expect(find.textContaining('ENOSPC'), findsNothing);
      expect(find.text('Details'), findsOneWidget);
    });

    testWidgets('progress is themed and calm', (tester) async {
      await pumpView(tester, null);
      await tester.pump();
      expectThemed(tester, 'Updating to OpenCode 2');
      expect(
        find.text('Moving your conversations to OpenCode 2…'),
        findsOneWidget,
      );
    });

    testWidgets('a separate history offers no pointless retry', (tester) async {
      await pumpView(
        tester,
        const ManagedMoveAttempt.failure(ManagedMoveReason.separateHistory),
      );
      await tester.pump();
      expect(find.text('Try again'), findsNothing);
    });
  });

  group('ManagedMoveRunner waits and retries before failing', () {
    late List<Duration> slept;
    ManagedMoveRunner runner({Duration ready = const Duration(seconds: 6)}) =>
        ManagedMoveRunner(
          backoff: const [
            Duration(seconds: 8),
            Duration(seconds: 20),
            Duration(seconds: 45),
          ],
          readyTimeout: ready,
          readyPoll: const Duration(seconds: 2),
          sleep: (d) async => slept.add(d),
        );

    setUp(() => slept = []);

    test('a phone that becomes ready later succeeds with no failure', () async {
      var calls = 0;
      final waiting = <int>[];
      final result = await runner().run(
        attempt: () async => ++calls < 3
            ? const ManagedMoveAttempt.failure(ManagedMoveReason.phoneNotReady)
            : const ManagedMoveAttempt.success(),
        onWaiting: (retry, of) => waiting.add(retry),
      );
      expect(result.ok, isTrue);
      expect(calls, 3);
      expect(waiting, [1, 2]);
      expect(slept, [const Duration(seconds: 8), const Duration(seconds: 20)]);
    });

    test('gives up after the last backoff with the last reason', () async {
      var calls = 0;
      final result = await runner().run(
        attempt: () async {
          calls++;
          return const ManagedMoveAttempt.failure(
            ManagedMoveReason.moveStopped,
            details: 'busy',
          );
        },
      );
      expect(calls, 4);
      expect(result.reason, ManagedMoveReason.moveStopped);
      expect(result.details, 'busy');
      expect(
        slept.fold<Duration>(Duration.zero, (a, b) => a + b),
        const Duration(seconds: 73),
      );
    });

    test('a separate history is final: no retry', () async {
      var calls = 0;
      final result = await runner().run(
        attempt: () async {
          calls++;
          return const ManagedMoveAttempt.failure(
            ManagedMoveReason.separateHistory,
          );
        },
      );
      expect(calls, 1);
      expect(result.reason, ManagedMoveReason.separateHistory);
      expect(slept, isEmpty);
    });

    test('waits a bounded time for the phone to be ready', () async {
      var polls = 0;
      final result = await runner().run(
        ready: () async => ++polls >= 3,
        attempt: () async => const ManagedMoveAttempt.success(),
      );
      expect(result.ok, isTrue);
      expect(polls, 3);
      expect(slept, [const Duration(seconds: 2), const Duration(seconds: 2)]);
    });

    test(
      'a phone that never answers is tried anyway after the bound',
      () async {
        var attempts = 0;
        await runner().run(
          ready: () async => throw StateError('not up'),
          attempt: () async {
            attempts++;
            return const ManagedMoveAttempt.success();
          },
        );
        expect(attempts, 1);
        // 6s bound at 2s polls: three pauses.
        expect(slept, hasLength(3));
      },
    );

    test('a thrown error becomes a failure, not a crash', () async {
      final result = await runner().run(
        attempt: () async => throw StateError('boom'),
      );
      expect(result.reason, ManagedMoveReason.moveStopped);
      expect(result.details, contains('boom'));
    });
  });
}
