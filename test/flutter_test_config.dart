import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/diagnostics/perf_trace.dart';
import 'package:agentphone/ui/kit/kit_motion.dart';

import 'golden_tolerance.dart';

/// Runs before every test file. The performance tracer writes one device-log
/// line per span in the app; in the suite those lines would only bury real
/// failures, so the buffer stays on and the log goes quiet.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  PerfTrace.logSink = null;
  // Ambient loops never settle; entrances (finite) still play, so
  // pumpAndSettle waits for them and goldens show the finished drawing.
  KitMotion.loops = false;
  // Goldens compare exactly, except the images named in
  // test/goldens/tolerances.json (see golden_tolerance.dart). A run with
  // --update-goldens keeps flutter's own updating comparator.
  final current = goldenFileComparator;
  if (!autoUpdateGoldenFiles && current is LocalFileComparator) {
    goldenFileComparator = TolerantGoldenComparator(
      current.basedir.resolve('golden_test.dart'),
      TolerantGoldenComparator.loadTolerances(),
    );
  }
  await testMain();
}
