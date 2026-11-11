import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter_test/flutter_test.dart';

import 'golden_tolerance.dart';

/// A 100x100 white PNG with [differing] black-red pixels in the first row(s).
Future<Uint8List> _png(int differing) async {
  const w = 100, h = 100;
  final pixels = Uint8List(w * h * 4)..fillRange(0, w * h * 4, 255);
  for (var i = 0; i < differing; i++) {
    pixels[i * 4] = 0;
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
  final desc = ui.ImageDescriptor.raw(
    buffer,
    width: w,
    height: h,
    pixelFormat: ui.PixelFormat.rgba8888,
  );
  final codec = await desc.instantiateCodec();
  final image = (await codec.getNextFrame()).image;
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the test config installs the tolerant comparator', () {
    expect(goldenFileComparator, isA<TolerantGoldenComparator>());
  });

  testWidgets('exact by default, tolerant only for a listed image', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('golden_tol');
    addTearDown(() => dir.deleteSync(recursive: true));
    final master = (await tester.runAsync(() => _png(0)))!;
    final near = (await tester.runAsync(() => _png(50)))!; // 0.5%
    File('${dir.path}/listed.png').writeAsBytesSync(master);
    File('${dir.path}/unlisted.png').writeAsBytesSync(master);
    final comparator = TolerantGoldenComparator(
      Uri.file('${dir.path}/x_test.dart'),
      {'listed.png': 1.0},
    );
    // File reads are real async work, so they run outside the fake clock.
    Future<bool> passes(TolerantGoldenComparator c, String name) async {
      final result = await tester.runAsync(() async {
        try {
          return await c.compare(near, Uri.parse(name));
        } on FlutterError {
          return false;
        }
      });
      return result!;
    }

    expect(await passes(comparator, 'listed.png'), isTrue);
    expect(await passes(comparator, 'unlisted.png'), isFalse);
    final tight = TolerantGoldenComparator(
      Uri.file('${dir.path}/x_test.dart'),
      {'listed.png': 0.1},
    );
    expect(await passes(tight, 'listed.png'), isFalse);
  });
}
