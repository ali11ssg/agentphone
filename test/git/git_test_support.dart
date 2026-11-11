import 'dart:convert';

import 'package:agentphone/domain/git/git_credentials.dart';
import 'package:agentphone/domain/git/git_shell.dart';

/// A fake token shaped like GitHub's; it must never show up in a script,
/// argv, Details or test output.
const fakeGitHubToken = 'gho_FAKEtoken0123456789abcdefFAKE42';

/// One step's canned answer.
typedef StepAnswer = ({int exit, String out, String err});

StepAnswer ok([String out = '']) => (exit: 0, out: out, err: '');
StepAnswer failed(String err, {int exit = 1, String out = ''}) =>
    (exit: exit, out: out, err: err);

/// The envelope a real script prints for [steps], in order.
String envelope(Map<String, StepAnswer> steps, {String noise = ''}) {
  String b64(String s) => base64.encode(utf8.encode(s));
  final b = StringBuffer()
    ..write(noise)
    ..writeln('@@OCG begin');
  for (final entry in steps.entries) {
    b
      ..writeln('@@OCG out ${entry.key} ${b64(entry.value.out)}')
      ..writeln('@@OCG err ${entry.key} ${b64(entry.value.err)}')
      ..writeln('@@OCG exit ${entry.key} ${entry.value.exit}');
  }
  b.writeln('@@OCG end');
  return b.toString();
}

/// Answers each script with the next canned envelope; records every script.
class FakeGitShell implements GitShell {
  FakeGitShell(this.answers);

  final List<Object> answers;
  final scripts = <String>[];
  final timeouts = <Duration>[];

  @override
  Future<String> run(String script, {required Duration timeout}) async {
    scripts.add(script);
    timeouts.add(timeout);
    if (answers.isEmpty) throw StateError('no answer for script');
    final next = answers.removeAt(0);
    if (next is Exception) throw next;
    if (next is String Function(String)) return next(script);
    return next as String;
  }
}

/// Records place/remove; can be told to fail placing.
class FakeCredentialDrop implements GitCredentialDrop {
  FakeCredentialDrop({this.failPlace = false});

  final bool failPlace;
  final placed = <String>[];
  final removed = <String>[];
  final secrets = <String>[];
  var _n = 0;

  bool get allRemoved =>
      placed.length == removed.length && placed.every(removed.contains);

  @override
  Future<GitSecretFile> place(String secret) async {
    if (failPlace) throw StateError('chmod refused');
    secrets.add(secret);
    final path = '/root/.oc-git/c-test${_n++}';
    placed.add(path);
    return GitSecretFile(shellPath: path, hostPath: '/host$path');
  }

  @override
  Future<void> remove(GitSecretFile file) async => removed.add(file.shellPath);
}
