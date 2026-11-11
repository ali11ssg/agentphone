import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Whether [c] is a red (or red-pink) the owner rule forbids: hue within
/// 12 degrees of red, clearly saturated and not dark.
bool isRedHue(Color? c0) {
  final c = c0;
  if (c == null) return false;
  return _red(c);
}

bool _red(Color c) {
  final hsv = HSVColor.fromColor(c);
  return (hsv.hue <= 12 || hsv.hue >= 345) &&
      hsv.saturation >= .45 &&
      hsv.value >= .45;
}

/// A colour that is not red.
final Matcher isNotRed = predicate<Color>(
  (c) => !isRedHue(c),
  'is not a red colour',
);

/// Every colour painted under [root]: icon and text colours, button fills and
/// foregrounds, and box / shape / material fills (translucent ones included,
/// since a tint of red is still red).
List<Color> paintedColours(WidgetTester tester, Finder root) {
  final out = <Color>[];
  void add(Color? c) {
    if (c != null) out.add(c);
  }

  for (final e
      in find.descendant(of: root, matching: find.byType(Icon)).evaluate()) {
    add((e.widget as Icon).color);
  }
  for (final e
      in find
          .descendant(of: root, matching: find.byType(RichText))
          .evaluate()) {
    final span = (e.widget as RichText).text;
    add(span.style?.color);
    span.visitChildren((s) {
      if (s is TextSpan) add(s.style?.color);
      return true;
    });
  }
  for (final e
      in find
          .descendant(of: root, matching: find.byType(ButtonStyleButton))
          .evaluate()) {
    final style = (e.widget as ButtonStyleButton).style;
    add(style?.backgroundColor?.resolve(const {}));
    add(style?.foregroundColor?.resolve(const {}));
  }
  for (final e
      in find
          .descendant(of: root, matching: find.byType(DecoratedBox))
          .evaluate()) {
    final d = (e.widget as DecoratedBox).decoration;
    if (d is BoxDecoration) add(d.color);
    if (d is ShapeDecoration) add(d.color);
  }
  for (final e
      in find
          .descendant(of: root, matching: find.byType(Container))
          .evaluate()) {
    final d = (e.widget as Container).decoration;
    if (d is BoxDecoration) add(d.color);
  }
  for (final e
      in find
          .descendant(of: root, matching: find.byType(Material))
          .evaluate()) {
    add((e.widget as Material).color);
  }
  return out;
}
