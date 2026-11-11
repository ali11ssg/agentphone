// Owner rule (LOOK-5): a destructive kit action is never painted in the
// error colour. The `destructive` flag keeps its ordering meaning (last in a
// group or menu, apart from the frequent actions) and the confirmation guards
// the act; the label, glyph and title stay neutral.
//
// There is no allowed red: the confirmed primary inside a confirmation is the
// strong neutral (`text1` fill), covered by kit_confirm_sheet_look_test.dart.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/l10n/app_localizations.dart';
import 'package:agentphone/ui/app_theme.dart';
import 'package:agentphone/ui/kit/kit.dart';

import '../support/no_red.dart';

/// Every text and icon colour painted under [root].
List<Color> _inks(WidgetTester tester, Finder root) {
  final out = <Color>[];
  for (final e
      in find
          .descendant(of: root, matching: find.byType(RichText))
          .evaluate()) {
    final span = (e.widget as RichText).text;
    span.visitChildren((s) {
      if (s is TextSpan && s.style?.color != null) out.add(s.style!.color!);
      return true;
    });
    if (span is TextSpan && span.style?.color != null) {
      out.add(span.style!.color!);
    }
  }
  for (final e
      in find.descendant(of: root, matching: find.byType(Icon)).evaluate()) {
    final c = (e.widget as Icon).color;
    if (c != null) out.add(c);
  }
  return out;
}

Future<void> _pump(WidgetTester tester, Widget body) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Center(child: body)),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('a destructive KitRow title is not the error colour', (
    tester,
  ) async {
    await _pump(
      tester,
      KitRow(
        key: const Key('row'),
        title: 'Remove thing',
        destructive: true,
        onTap: () {},
      ),
    );
    final inks = _inks(tester, find.byKey(const Key('row')));
    expect(inks, isNotEmpty);
    expect(inks.where(isRedHue), isEmpty);
  });

  for (final role in [KitButtonRole.secondary, KitButtonRole.tertiary]) {
    testWidgets(
      'a destructive ${role.name} KitButton is not the error colour',
      (tester) async {
        await _pump(
          tester,
          KitButton(
            key: const Key('button'),
            role: role,
            label: 'Stop setup',
            icon: Icons.stop,
            destructive: true,
            onPressed: () {},
          ),
        );
        final inks = _inks(tester, find.byKey(const Key('button')));
        expect(inks, isNotEmpty);
        expect(inks.where(isRedHue), isEmpty);
        final button = tester.widget<ButtonStyleButton>(
          find.descendant(
            of: find.byKey(const Key('button')),
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          ),
        );
        expect(button.style?.foregroundColor?.resolve(const {}), isNotRed);
      },
    );
  }

  testWidgets('a destructive KitIconButton glyph is not the error colour', (
    tester,
  ) async {
    await _pump(
      tester,
      KitIconButton(
        key: const Key('icon'),
        icon: Icons.delete,
        tooltip: 'Delete',
        destructive: true,
        onPressed: () {},
      ),
    );
    final inks = _inks(tester, find.byKey(const Key('icon')));
    expect(inks, isNotEmpty);
    expect(inks.where(isRedHue), isEmpty);
  });

  testWidgets('a destructive KitMenu item is not the error colour', (
    tester,
  ) async {
    late BuildContext anchor;
    await _pump(
      tester,
      Builder(
        builder: (context) {
          anchor = context;
          return const SizedBox();
        },
      ),
    );
    unawaited(
      showKitMenu(
        anchor,
        menuKey: const Key('menu'),
        items: [
          KitMenuItem(label: 'Details', onSelected: () {}),
          KitMenuItem(
            label: 'Stop it',
            icon: Icons.stop,
            destructive: true,
            onSelected: () {},
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    final inks = _inks(tester, find.byKey(const Key('menu')));
    expect(inks, isNotEmpty);
    expect(inks.where(isRedHue), isEmpty);
  });
}
