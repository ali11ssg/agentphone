import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/domain/git/git_credentials.dart';
import 'package:agentphone/domain/git/git_models.dart';
import 'package:agentphone/domain/git/git_problem.dart';
import 'package:agentphone/domain/git/git_repository.dart';
import 'package:agentphone/domain/git/git_shell.dart';

import 'git_fixtures.dart' as fx;
import 'git_test_support.dart';

const _dir = '/root/projects/my app';
const _git = "'git' '--no-pager' '-c' 'color.ui=false'";

GitRepository _repo(FakeGitShell shell, {FakeCredentialDrop? drop}) =>
    GitRepository(shell: shell, directory: _dir, credentials: drop);

void main() {
  group('snapshot', () {
    test('one round trip reads everything and parses it', () async {
      final shell = FakeGitShell([
        envelope({
          'status': ok(fx.statusRename),
          'unstaged': ok(fx.numstatWork),
          'staged': ok(fx.numstatIndex),
          'log': ok(fx.log),
          'branches': ok(fx.branches),
          'operation': ok(''),
          'remotes': ok('remote.origin.url git@github.com:o/r.git\n'),
        }),
      ]);
      final result = await _repo(shell).snapshot();
      final snapshot = (result as GitSnapshotReady).snapshot;
      expect(snapshot.status.files, hasLength(4));
      expect(snapshot.commits, hasLength(2));
      expect(snapshot.branches.current!.name, 'main');
      expect(snapshot.pushRemote!.kind, GitRemoteKind.gitHubSsh);
      expect(snapshot.operation, GitOperation.none);
      expect(shell.scripts, hasLength(1));
      final script = shell.scripts.single;
      expect(script, contains("cd -- '/root/projects/my app'"));
      expect(
        script,
        contains(
          "ocg_s status $_git 'status' '--porcelain=v2' '--branch' '-z' "
          "'--untracked-files=normal' || {",
        ),
      );
      expect(
        script,
        contains("ocg_s staged $_git 'diff' '--cached' '--numstat' '-z'\n"),
      );
      expect(
        script,
        contains("ocg_s log $_git 'log' '-n' '30' '-z' '--format="),
      );
    });

    test('"not a repository" is a state, not an error', () async {
      final shell = FakeGitShell([
        envelope({'status': failed(fx.notRepositoryError, exit: 128)}),
      ]);
      expect(await _repo(shell).snapshot(), isA<GitSnapshotNotRepository>());
    });

    test('an unborn branch reads with an empty history', () async {
      final shell = FakeGitShell([
        envelope({
          'status': ok(fx.statusUnborn),
          'unstaged': ok(),
          'staged': ok('1\t0\ta b.txt\x00'),
          'log': failed(fx.logUnbornError, exit: 128),
          'branches': ok(),
          'operation': ok(),
          'remotes': ok(),
        }),
      ]);
      final snapshot =
          ((await _repo(shell).snapshot()) as GitSnapshotReady).snapshot;
      expect(snapshot.status.branch.unborn, isTrue);
      expect(snapshot.commits, isEmpty);
      expect(snapshot.status.files.single.stagedAddedLines, 1);
    });

    test('half-done merge and conflicts are typed', () async {
      final shell = FakeGitShell([
        envelope({
          'status': ok(fx.statusConflict),
          'unstaged': ok(),
          'staged': ok(),
          'log': ok(fx.log),
          'branches': ok(fx.branches),
          'operation': ok('MERGE_HEAD\n'),
          'remotes': ok(),
        }),
      ]);
      final snapshot =
          ((await _repo(shell).snapshot()) as GitSnapshotReady).snapshot;
      expect(snapshot.operation, GitOperation.merge);
      expect(snapshot.status.hasConflicts, isTrue);
    });

    test('bridge and envelope failures map to problems', () async {
      Future<GitProblem?> problemOf(Object answer) async {
        final result = await _repo(FakeGitShell([answer])).snapshot();
        return (result as GitSnapshotFailed).failure.problem;
      }

      expect(
        await problemOf('@@OCG begin\n@@OCG nogit\n'),
        GitProblem.gitMissing,
      );
      expect(
        await problemOf('@@OCG begin\n@@OCG nodir\n'),
        GitProblem.folderMissing,
      );
      expect(await problemOf('garbage'), GitProblem.outputTooLarge);
      expect(
        await problemOf(const GitShellException(GitShellFailure.unsupported)),
        GitProblem.serverCannotRunCommands,
      );
      expect(
        await problemOf(const GitShellException(GitShellFailure.timedOut)),
        GitProblem.timedOut,
      );
      // An answer with a step missing although nothing stopped it.
      expect(
        await problemOf(envelope({'status': ok(fx.statusRename)})),
        GitProblem.outputTooLarge,
      );
    });
  });

  group('commit', () {
    test('stages and commits exactly the chosen paths, quoted', () async {
      final shell = FakeGitShell([
        envelope({'add': ok(), 'commit': ok(), 'id': ok('abc1234\n')}),
      ]);
      const message = 'it\'s "fine" \$(rm -rf ~) `x`\nsecond line';
      final result = await _repo(shell).commit(
        paths: const ['new näme ✓.txt', "a 'b'.txt", '-rf'],
        message: message,
      );
      expect(result.ok, isTrue);
      expect(result.note, GitActionNote.committed);
      expect(result.commit, 'abc1234');
      final script = shell.scripts.single;
      expect(
        script,
        contains(
          "ocg_s add $_git 'add' '-A' '--' 'new näme ✓.txt' "
          r"'a '\''b'\''.txt' '-rf' || {",
        ),
      );
      expect(
        script,
        contains(
          "ocg_s commit $_git 'commit' '-m' "
          r"""'it'\''s "fine" $(rm -rf ~) `x`"""
          "\nsecond line' '--' 'new näme ✓.txt' "
          r"'a '\''b'\''.txt' '-rf' || {",
        ),
      );
    });

    test('nothing chosen and an empty message never run a command', () async {
      final shell = FakeGitShell([]);
      final repo = _repo(shell);
      expect(
        (await repo.commit(paths: const [], message: 'm')).problem,
        GitProblem.nothingSelected,
      );
      expect(
        (await repo.commit(paths: const ['a'], message: '  ')).problem,
        GitProblem.emptyMessage,
      );
      expect(shell.scripts, isEmpty);
    });

    test('missing identity is typed; Git text kept for Details', () async {
      final shell = FakeGitShell([
        envelope({'add': ok(), 'commit': failed(fx.identityError, exit: 128)}),
      ]);
      final result = await _repo(
        shell,
      ).commit(paths: const ['a'], message: 'm');
      expect(result.problem, GitProblem.identityMissing);
      expect(result.failure!.details, contains('Please tell me who you are'));
    });

    test('"nothing to commit" on stdout is read too', () async {
      final shell = FakeGitShell([
        envelope({
          'add': ok(),
          'commit': failed('', out: 'nothing to commit, working tree clean\n'),
        }),
      ]);
      expect(
        (await _repo(shell).commit(paths: const ['a'], message: 'm')).problem,
        GitProblem.nothingToCommit,
      );
    });
  });

  group('pull', () {
    test('ff-only; no upstream and detached are typed', () async {
      final noUpstream = FakeGitShell([
        envelope({
          'head': ok('lonely\n'),
          'upstream': failed(
            'fatal: no upstream configured for branch \'lonely\'\n',
            exit: 128,
          ),
        }),
      ]);
      expect((await _repo(noUpstream).pull()).problem, GitProblem.noUpstream);

      final detached = FakeGitShell([
        envelope({'head': failed('', exit: 1)}),
      ]);
      expect((await _repo(detached).pull()).problem, GitProblem.detachedHead);
    });

    test('cannot fast-forward is a typed result', () async {
      final shell = FakeGitShell([
        envelope({
          'head': ok('main\n'),
          'upstream': ok('origin/main\n'),
          'pull': failed(fx.pullCannotFastForwardError, exit: 128),
        }),
      ]);
      final result = await _repo(shell).pull();
      expect(result.problem, GitProblem.cannotFastForward);
      expect(
        shell.scripts.single,
        contains("ocg_s pull $_git 'pull' '--ff-only' '--no-rebase'\n"),
      );
    });

    test('already up to date', () async {
      final shell = FakeGitShell([
        envelope({
          'head': ok('main\n'),
          'upstream': ok('origin/main\n'),
          'pull': ok('Already up to date.\n'),
        }),
      ]);
      expect((await _repo(shell).pull()).note, GitActionNote.upToDate);
    });
  });

  group('push', () {
    test('first push sets the upstream on origin', () async {
      final shell = FakeGitShell([
        envelope({
          'head': ok('feature/x\n'),
          'upstream': failed('fatal: no upstream configured\n', exit: 128),
          'remotes': ok('mirror\norigin\n'),
        }),
        envelope({'push': ok()}),
      ]);
      final result = await _repo(shell).push();
      expect(result.note, GitActionNote.pushedAndTracking);
      expect(
        shell.scripts[1],
        contains(
          "ocg_s push $_git 'push' '--set-upstream' 'origin' 'feature/x'\n",
        ),
      );
    });

    test('no remote at all is typed', () async {
      final shell = FakeGitShell([
        envelope({
          'head': ok('main\n'),
          'upstream': failed('fatal: no upstream configured\n', exit: 128),
          'remotes': ok(),
        }),
      ]);
      expect((await _repo(shell).push()).problem, GitProblem.noRemote);
      expect(shell.scripts, hasLength(1));
    });

    test('rejected push says pull first', () async {
      final shell = FakeGitShell([
        envelope({
          'head': ok('main\n'),
          'upstream': ok('origin/main\n'),
          'remotes': ok('origin\n'),
        }),
        envelope({'push': failed(fx.pushRejectedError)}),
      ]);
      final result = await _repo(shell).push();
      expect(result.problem, GitProblem.pushRejected);
      expect(result.failure!.details, contains('[rejected]'));
    });
  });

  group('GitHub token hand-off', () {
    Future<(GitActionResult, FakeGitShell, FakeCredentialDrop)> pushWith(
      StepAnswer push, {
      FakeCredentialDrop? drop,
    }) async {
      final shell = FakeGitShell([
        envelope({
          'head': ok('main\n'),
          'upstream': ok('origin/main\n'),
          'remotes': ok('origin\n'),
        }),
        envelope({'push': push}),
      ]);
      final credentials = drop ?? FakeCredentialDrop();
      final result = await _repo(
        shell,
        drop: credentials,
      ).push(gitHubToken: fakeGitHubToken);
      return (result, shell, credentials);
    }

    test('the token is only in the 0600 file, never in a script', () async {
      final (result, shell, drop) = await pushWith(ok());
      expect(result.note, GitActionNote.pushed);
      expect(drop.secrets, [fakeGitHubToken]);
      for (final script in shell.scripts) {
        expect(script, isNot(contains(fakeGitHubToken)));
        expect(script, isNot(contains('FAKEtoken')));
      }
      final push = shell.scripts[1];
      final file = drop.placed.single;
      expect(push, contains("OC_TOKEN_FILE='$file'; export OC_TOKEN_FILE"));
      expect(push, contains("rm -f -- '\\''$file'\\''"));
      expect(
        push,
        contains("'-c' 'credential.helper=' '-c' 'credential.helper=!f()"),
      );
      expect(
        push,
        contains("'-c' 'url.https://github.com/.insteadOf=git@github.com:'"),
      );
      expect(
        push.indexOf("'credential.helper='"),
        lessThan(push.indexOf("'credential.helper=!f()")),
      );
      expect(push, contains('GIT_TERMINAL_PROMPT'));
      expect(drop.allRemoved, isTrue);
    });

    test('the file is removed when the push fails', () async {
      final (result, shell, drop) = await pushWith(failed(fx.httpsAuthError));
      expect(result.problem, GitProblem.gitHubTokenRejected);
      expect(result.failure!.details, isNot(contains(fakeGitHubToken)));
      expect(drop.allRemoved, isTrue);
    });

    test('the file is removed when the bridge throws', () async {
      final drop = FakeCredentialDrop();
      final shell = FakeGitShell([
        envelope({
          'head': ok('main\n'),
          'upstream': ok('origin/main\n'),
          'remotes': ok('origin\n'),
        }),
        const GitShellException(GitShellFailure.unavailable),
      ]);
      final result = await _repo(
        shell,
        drop: drop,
      ).push(gitHubToken: fakeGitHubToken);
      expect(result.problem, GitProblem.environmentUnavailable);
      expect(drop.placed, hasLength(1));
      expect(drop.allRemoved, isTrue);
    });

    test('a file that cannot be made private means no push', () async {
      final shell = FakeGitShell([]);
      final result = await _repo(
        shell,
        drop: FakeCredentialDrop(failPlace: true),
      ).push(gitHubToken: fakeGitHubToken);
      expect(result.problem, GitProblem.environmentUnavailable);
      expect(shell.scripts, isEmpty);
    });

    test('no drop (Termux, servers): the token is never used', () async {
      final shell = FakeGitShell([
        envelope({
          'head': ok('main\n'),
          'upstream': ok('origin/main\n'),
          'remotes': ok('origin\n'),
        }),
        envelope({'push': failed(fx.httpsAuthError)}),
      ]);
      final result = await _repo(shell).push(gitHubToken: fakeGitHubToken);
      expect(result.problem, GitProblem.authRequired);
      expect(shell.scripts.join(), isNot(contains('credential.helper')));
      expect(shell.scripts.join(), isNot(contains(fakeGitHubToken)));
    });

    test('the helper names only the variable', () {
      expect(gitHubCredentialHelper, contains(r'$OC_TOKEN_FILE'));
      expect(gitHubCredentialHelper, contains('github.com'));
    });
  });

  group('branches and discard', () {
    test('invalid branch names never reach a shell', () async {
      final shell = FakeGitShell([]);
      final repo = _repo(shell);
      for (final name in [
        '',
        '-rf',
        'a b',
        'a..b',
        'a/',
        '.hidden',
        'x.lock',
        'a~1',
        'a:b',
        '@',
        r'a\b',
        'a[b',
      ]) {
        expect(
          (await repo.createBranch(name)).problem,
          GitProblem.invalidBranchName,
          reason: name,
        );
      }
      expect(shell.scripts, isEmpty);
      expect(isValidGitBranchName('feature/näme-1'), isTrue);
    });

    test('switch and create run git switch', () async {
      final shell = FakeGitShell([
        envelope({'run': ok()}),
        envelope({
          'run': failed(
            "fatal: a branch named 'x' already exists\n",
            exit: 128,
          ),
        }),
      ]);
      final repo = _repo(shell);
      expect(
        (await repo.switchBranch('feature/x')).note,
        GitActionNote.switched,
      );
      expect(
        shell.scripts[0],
        contains("ocg_s run $_git 'switch' 'feature/x'\n"),
      );
      expect((await repo.createBranch('x')).problem, GitProblem.branchExists);
      expect(shell.scripts[1], contains("ocg_s run $_git 'switch' '-c' 'x'\n"));
    });

    test('discard picks the command by the kind of change', () async {
      final shell = FakeGitShell([
        envelope({'discard': ok()}),
        envelope({'discard': ok()}),
        envelope({'discard': ok()}),
        envelope({'remove': ok(), 'discard': ok()}),
      ]);
      final repo = _repo(shell);
      await repo.discard(
        const GitFileChange(path: 'a b.txt', unstaged: GitChangeKind.modified),
      );
      await repo.discard(
        const GitFileChange(path: 'new.txt', unstaged: GitChangeKind.untracked),
      );
      await repo.discard(
        const GitFileChange(path: 'added.txt', staged: GitChangeKind.added),
      );
      await repo.discard(
        const GitFileChange(
          path: 'new näme ✓.txt',
          originalPath: 'old name.txt',
          staged: GitChangeKind.renamed,
        ),
      );
      expect(
        shell.scripts[0],
        contains(
          "ocg_s discard $_git 'restore' '--staged' '--worktree' '--' 'a b.txt'\n",
        ),
      );
      expect(
        shell.scripts[1],
        contains("ocg_s discard $_git 'clean' '-f' '-q' '--' 'new.txt'\n"),
      );
      expect(
        shell.scripts[2],
        contains("ocg_s discard $_git 'rm' '-f' '-q' '--' 'added.txt'\n"),
      );
      expect(
        shell.scripts[3],
        contains(
          "ocg_s remove $_git 'rm' '-f' '-q' '--' 'new näme ✓.txt' || {",
        ),
      );
      expect(
        shell.scripts[3],
        contains(
          "ocg_s discard $_git 'restore' '--staged' '--worktree' '--' "
          "'old name.txt'\n",
        ),
      );
    });

    test('a conflicted file is never discarded', () async {
      final shell = FakeGitShell([]);
      final result = await _repo(shell).discard(
        const GitFileChange(
          path: 'keep.txt',
          conflict: GitConflictKind.bothModified,
        ),
      );
      expect(result.problem, GitProblem.cannotDiscardConflict);
      expect(shell.scripts, isEmpty);
    });
  });
}
