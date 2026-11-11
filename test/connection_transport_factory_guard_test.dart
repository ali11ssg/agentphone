import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Location changes must rebuild through the shared transport builder so
/// profile-scoped gateway selection and injected transports stay consistent.
/// The controller library includes connection.dart and all its part files.
String _connectionLibrarySource() {
  final parts =
      Directory('lib/state/connection')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  return [
    File('lib/state/connection.dart'),
    ...parts,
  ].map((file) => file.readAsStringSync()).join('\n');
}

void main() {
  test('the location rescope path uses the shared transport builder', () {
    final source = _connectionLibrarySource();
    // _selectLocation only wraps the rescope in a performance span; the
    // body that rebuilds the transport is _selectLocationUntraced.
    final start = source.indexOf('Future<void> _selectLocationUntraced(');
    expect(start, isNot(-1), reason: '_selectLocationUntraced is missing');

    // The rescope rebuilds the transport after the early-return branch; look
    // at the body that follows, not the whole file.
    final body = source.substring(start, start + 2500);
    expect(
      body.contains('_buildTransportPair(profile)'),
      isTrue,
      reason:
          '_selectLocation must rebuild through _buildTransportPair so the '
          'profile keeps its selected transport when the directory changes.',
    );
  });
}
