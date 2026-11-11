import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/l10n/app_localizations.dart';
import 'package:agentphone/ui/kit/kit.dart';

Widget _app(Widget home) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: home),
);

void main() {
  testWidgets('a claimed link is not sent to the external-link gate', (
    tester,
  ) async {
    final claimed = <String>[];
    await tester.pumpWidget(
      _app(
        KitLinkScope(
          claim: (context, url) {
            final mine = Uri.parse(url).host == 'localhost';
            if (mine) claimed.add(url);
            return mine;
          },
          child: Builder(
            builder: (context) => Column(
              children: [
                TextButton(
                  onPressed: () =>
                      KitLinkScope.open(context, 'http://localhost:5173'),
                  child: const Text('local'),
                ),
                TextButton(
                  onPressed: () =>
                      KitLinkScope.open(context, 'https://example.com'),
                  child: const Text('web'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('local'));
    await tester.pumpAndSettle();
    expect(claimed, ['http://localhost:5173']);
    expect(find.text('Open external link?'), findsNothing);
    await tester.tap(find.text('web'));
    await tester.pumpAndSettle();
    expect(claimed.length, 1);
    expect(find.text('Open external link?'), findsOneWidget);
  });

  testWidgets('with no scope every link goes to the external-link gate', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                KitLinkScope.open(context, 'http://localhost:5173'),
            child: const Text('local'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('local'));
    await tester.pumpAndSettle();
    // Unclaimed, a localhost link is just an http link: it asks first.
    expect(find.text('Open insecure HTTP link?'), findsOneWidget);
  });
}
