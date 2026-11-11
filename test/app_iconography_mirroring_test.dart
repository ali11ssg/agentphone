import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Pins which glyphs mirror in right-to-left. Only glyphs that point along
/// the reading direction may; everything else (objects, clocks, checks,
/// media controls, vertical arrows) keeps its drawing.
void main() {
  test('exactly the reading-direction glyphs mirror', () {
    final source = File('lib/ui/app_iconography.dart').readAsStringSync();
    final entries = RegExp(
      r'static const (\w+) = IconData\(\s*0x[0-9a-f]+,\s*'
      r"fontFamily: '\w+',\s*matchTextDirection: (true|false),",
    ).allMatches(source);
    expect(entries.length, greaterThan(150));
    final mirrored = {
      for (final m in entries)
        if (m.group(2) == 'true') m.group(1)!,
    };
    expect(mirrored, {
      'back',
      'forward',
      'chevronLeft',
      'chevronRight',
      // Vertical and symmetric: mirroring changes nothing; kept as it was.
      'chevronUp',
      'chevronDown',
      'nested',
      'reply',
      'undo',
      'login',
      'externalLink',
      'returnKey',
    });
  });
}
