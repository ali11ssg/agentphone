import 'dart:async';

import 'package:flutter/widgets.dart';

import 'kit_scanner.dart';

KitScannerCamera qrCamera() => const _DisabledQrCamera();

/// AgentPhone does not ask for the camera permission, so the QR scanner has
/// no frames to read. The camera is replaced by this no-op: opening the
/// scanner fails immediately with [KitScannerFailure], and the screen falls
/// back to the path that needs no camera — the user types or pastes the code.
/// The interface stays so the scanner screen, its tests and the rest of the
/// app keep their shape.
class _DisabledQrCamera implements KitScannerCamera {
  const _DisabledQrCamera();

  @override
  Future<void> start() async => throw const KitScannerFailure();

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}

  @override
  Stream<String> get codes => const Stream<String>.empty();

  @override
  Widget preview(BuildContext context) => const SizedBox.shrink();
}
