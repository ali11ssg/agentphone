import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/domain/git/git_script.dart';
import 'package:agentphone/domain/git/git_shell.dart';

import 'git_test_support.dart';

void main() {
  group('shQuote', () {
    test('single quotes stop every expansion', () {
      expect(shQuote('plain'), "'plain'");
      expect(shQuote("it's"), r"'it'\''s'");
      expect(
        shQuote(r'$(rm -rf ~) `x` "y" \z'),
        r"""'$(rm -rf ~) `x` "y" \z'""",
      );
      expect(shQuote('a\nb'), "'a\nb'");
      expect(shQuote(''), "''");
    });

    test('a NUL byte is refused, and the value is not echoed', () {
      expect(
        () => shQuote('a\x00b'),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.toString(),
            'text',
            isNot(contains('a\x00b')),
          ),
        ),
      );
    });

    test('shCommand quotes every word', () {
      expect(
        shCommand(['git', 'commit', '-m', "it's"]),
        r"'git' 'commit' '-m' 'it'\''s'",
      );
    });
  });

  test('the rendered script, whole', () {
    final script = GitScript(
      directory: "/root/projects/it's here",
      steps: const [
        GitStep('one', ['git', 'status'], stopOnFailure: true),
        GitStep('two', ['git', 'log']),
      ],
      environment: const {'OC_TOKEN_FILE': '/root/.oc-git/c-1'},
      removeOnExit: const ['/root/.oc-git/c-1'],
    ).render();
    expect(script, r"""printf '@@OCG begin\n'
cd -- '/root/projects/it'\''s here' 2>/dev/null || { printf '@@OCG nodir\n'; exit 0; }
command -v git >/dev/null 2>&1 || { printf '@@OCG nogit\n'; exit 0; }
ocg_t=$(mktemp -d 2>/dev/null) || { printf '@@OCG notemp\n'; exit 0; }
trap 'rm -rf "$ocg_t"; rm -f -- '\''/root/.oc-git/c-1'\''' EXIT
GIT_TERMINAL_PROMPT='0'; export GIT_TERMINAL_PROMPT
GIT_PAGER='cat'; export GIT_PAGER
PAGER='cat'; export PAGER
LC_ALL='C'; export LC_ALL
LANG='C'; export LANG
GIT_OPTIONAL_LOCKS='0'; export GIT_OPTIONAL_LOCKS
OC_TOKEN_FILE='/root/.oc-git/c-1'; export OC_TOKEN_FILE
ocg_s() {
  ocg_n=$1; shift
  "$@" >"$ocg_t/o" 2>"$ocg_t/e"; ocg_c=$?
  printf '@@OCG out %s ' "$ocg_n"; base64 <"$ocg_t/o" | tr -d '\n'; printf '\n'
  printf '@@OCG err %s ' "$ocg_n"; base64 <"$ocg_t/e" | tr -d '\n'; printf '\n'
  printf '@@OCG exit %s %s\n' "$ocg_n" "$ocg_c"
  return $ocg_c
}
ocg_s one 'git' 'status' || { printf '@@OCG end\n'; exit 0; }
ocg_s two 'git' 'log'
printf '@@OCG end\n'
""");
  });

  test('step names and variable names are checked', () {
    expect(
      () => const GitScript(
        directory: '/p',
        steps: [
          GitStep('bad name', ['git']),
        ],
      ).render(),
      throwsArgumentError,
    );
    expect(
      () => const GitScript(
        directory: '/p',
        steps: [],
        environment: {'bad;name': 'x'},
      ).render(),
      throwsArgumentError,
    );
  });

  group('envelope', () {
    test('decodes steps and ignores noise lines', () {
      final parsed = GitEnvelope.parse(
        envelope({
          'status': ok('a\x00b é'),
          'log': failed('fatal: x\n', exit: 128),
        }, noise: 'proot warning: can\'t sanitize binding "/proc/self/fd/1"\n'),
      );
      expect(parsed.problem, isNull);
      expect(parsed['status']!.stdout, 'a\x00b é');
      expect(parsed['status']!.ok, isTrue);
      expect(parsed['log']!.exitCode, 128);
      expect(parsed['log']!.stderr, 'fatal: x\n');
    });

    test('a cut-off answer is reported, not misread', () {
      final full = envelope({'status': ok('x' * 100)});
      // The in-app bridge keeps the tail: the first lines go.
      final tail = full.substring(full.indexOf('@@OCG err'));
      expect(GitEnvelope.parse(tail).problem, GitEnvelopeProblem.truncated);
      // An answer missing its end marker.
      final head = full.substring(0, full.indexOf('@@OCG end'));
      expect(GitEnvelope.parse(head).problem, GitEnvelopeProblem.truncated);
    });

    test('folder and git checks', () {
      expect(
        GitEnvelope.parse('@@OCG begin\n@@OCG nodir\n').problem,
        GitEnvelopeProblem.folderMissing,
      );
      expect(
        GitEnvelope.parse('@@OCG begin\n@@OCG nogit\n').problem,
        GitEnvelopeProblem.gitMissing,
      );
    });
  });
}
