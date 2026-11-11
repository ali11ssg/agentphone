import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/paseo/tested_versions.dart';

/// One Claude Code sign-in on the phone (docs/qa/claude-phone-auth-2026-10-16):
/// the app's native side must see a sign-in made in the Terminal, and must
/// accept every Claude build the app is qualified with.
void main() {
  const native = 'android/app/src/main/kotlin/io.github.agentphone.app';

  test('every app launch of Claude shares the Terminal sign-in folder', () {
    final linux = File('$native/BuiltinLinux.kt').readAsStringSync();
    String body(String signature) {
      final start = linux.indexOf(signature);
      expect(start, isNonNegative, reason: signature);
      // Up to the closing brace of that member.
      return linux.substring(start, linux.indexOf('\n    }\n', start));
    }

    // The sign-in terminal, and the helper/auth check/sign-in check (all
    // through startPrivateAgentProcess).
    expect(
      body('fun agentSignInCommand('),
      contains('shareClaudeSignIn(profileId)'),
    );
    expect(
      body('private fun startPrivateAgentProcess('),
      contains('shareClaudeSignIn(profileId)'),
    );
    expect(
      body('fun deleteAgentHome('),
      contains('PhoneAgentClaudeHome.forget('),
    );
  });

  test('the native sign-in check accepts every tested Claude build', () {
    final signIn = File('$native/PhoneAgentSignIn.kt').readAsStringSync();
    final declared = RegExp(
      r'TESTED_CLAUDE_VERSIONS = setOf\((.*)\)\n',
    ).firstMatch(signIn);
    expect(declared, isNotNull);
    final versions = RegExp(
      r'"([0-9.]+) \(Claude Code\)"',
    ).allMatches(declared!.group(1)!).map((m) => m.group(1)).toSet();
    expect(versions, claudeCodeTestedVersions);
    expect(signIn, isNot(contains('!= "2.1.283 (Claude Code)"')));
  });
}
