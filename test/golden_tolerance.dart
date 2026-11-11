import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter_test/flutter_test.dart';

/// Per-image tolerance for golden comparison, in percent of pixels.
///
/// Comparison is exact unless the image's file name is listed in
/// `test/goldens/tolerances.json` (`{"<name>.png": maxDiffPercent}`). The
/// listed Team screens rasterize blur and gradients a hair differently on the
/// build server's CPU than on the machine that wrote the masters; the list is
/// per image and never a global threshold, so a changed label still fails.
class TolerantGoldenComparator extends LocalFileComparator {
  TolerantGoldenComparator(super.testFile, this.tolerances);

  /// Max allowed difference in percent, by golden file name.
  final Map<String, double> tolerances;

  static Map<String, double>? _cache;

  /// Reads `test/goldens/tolerances.json` once per process.
  static Map<String, double> loadTolerances() => _cache ??= _read();

  static Map<String, double> _read() {
    for (var dir = Directory.current; ; dir = dir.parent) {
      final file = File('${dir.path}/test/goldens/tolerances.json');
      if (file.existsSync()) {
        final raw = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        return {
          for (final e in raw.entries)
            if (!e.key.startsWith('_')) e.key: (e.value as num).toDouble(),
        };
      }
      if (dir.parent.path == dir.path) return const {};
    }
  }

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final name = golden.pathSegments.last;
    final allowed = tolerances[name];
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    // diffPercent is a fraction of pixels (0..1); the list is in percent.
    final passed =
        result.passed ||
        (allowed != null && result.diffPercent * 100 <= allowed);
    if (passed) {
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}
