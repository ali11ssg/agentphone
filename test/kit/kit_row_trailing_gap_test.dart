// A row's text never runs into the value that trails it ("UnrestrictedOpen" on
// the Background screen): the text column ends before the value begins, at
// ordinary and large text, in both reading directions.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/ui/app_theme.dart';
import 'package:agentphone/ui/kit/kit.dart';

void main() {
  const detail =
      'In App info › Battery, choose Unrestricted or allow '
      'background running.';
  for (final direction in TextDirection.values) {
    for (final scale in [1.0, 2.5]) {
      testWidgets('text and Open do not touch ($direction, ${scale}x)', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: Directionality(textDirection: direction, child: child!),
            ),
            home: const Scaffold(
              body: SizedBox(
                width: 360,
                child: KitRow(
                  title: 'Allow background activity',
                  supporting: TextSpan(text: detail),
                  supportingMaxLines: 4,
                  trailing: KitRowValue('Open'),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        final text = tester.getRect(find.textContaining('In App info'));
        final open = tester.getRect(find.text('Open'));
        final gap = direction == TextDirection.ltr
            ? open.left - text.right
            : text.left - open.right;
        expect(gap, greaterThanOrEqualTo(4));
      });
    }
  }
}
