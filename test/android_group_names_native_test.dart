import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'native/kotlin_jar_cache.dart';

void main() {
  final compiler =
      Platform.environment['KOTLINC'] ??
      '${Platform.environment['HOME']}/.sdkman/candidates/kotlin/current/bin/kotlinc';
  final skip = File(compiler).existsSync() ? null : 'kotlinc unavailable';
  test(
    'the guest names the Android groups once, idempotently',
    skip: skip,
    () async {
      final jar = await cachedKotlinJar(
        compiler: compiler,
        sources: [
          'android/app/src/main/kotlin/io/github/agentphone/app/AndroidGroupNames.kt',
          'test/native/android_group_names_harness.kt',
        ],
      );
      final result = await Process.run('java', [
        '-cp',
        jar,
        'io.github.agentphone.app.Android_group_names_harnessKt',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stdout, contains('PASS android-group-names'));
    },
  );
}
