import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/domain/git/git_models.dart';
import 'package:agentphone/domain/git/git_parsers.dart';
import 'package:agentphone/domain/git/git_problem.dart';

import 'git_fixtures.dart' as fx;

void main() {
  group('status', () {
    test('rename to a unicode name with spaces, binary, edit, untracked', () {
      final status = parseGitStatus(fx.statusRename);
      expect(status.branch.head, 'main');
      expect(status.branch.upstream, 'origin/main');
      expect(status.branch.ahead, 0);
      expect(status.branch.behind, 0);
      expect(status.branch.commit, startsWith('b196b9f'));
      expect(status.files.map((f) => f.path), [
        'img.bin',
        'keep.txt',
        'new näme ✓.txt',
        'untracked file é.md',
      ]);
      final rename = status.files[2];
      expect(rename.staged, GitChangeKind.renamed);
      expect(rename.unstaged, isNull);
      expect(rename.originalPath, 'old name.txt');
      expect(status.files[0].staged, GitChangeKind.modified);
      expect(status.files[1].staged, isNull);
      expect(status.files[1].unstaged, GitChangeKind.modified);
      expect(status.files[3].isUntracked, isTrue);
      expect(status.hasConflicts, isFalse);
    });

    test('a merge conflict is a typed state with ahead count', () {
      final status = parseGitStatus(fx.statusConflict);
      expect(status.branch.ahead, 1);
      expect(status.hasConflicts, isTrue);
      final conflict = status.conflicts.single;
      expect(conflict.path, 'keep.txt');
      expect(conflict.conflict, GitConflictKind.bothModified);
      expect(conflict.isConflicted, isTrue);
    });

    test('detached HEAD has no branch name and no upstream', () {
      final status = parseGitStatus(fx.statusDetached);
      expect(status.branch.detached, isTrue);
      expect(status.branch.hasUpstream, isFalse);
      expect(status.branch.commit, startsWith('97f3f68'));
    });

    test('a branch without upstream is a typed state', () {
      final status = parseGitStatus(fx.statusNoUpstream);
      expect(status.branch.head, 'lonely');
      expect(status.branch.hasUpstream, isFalse);
      expect(status.branch.detached, isFalse);
    });

    test('an unborn branch has no commit; a path with a space survives', () {
      final status = parseGitStatus(fx.statusUnborn);
      expect(status.branch.unborn, isTrue);
      expect(status.branch.head, 'main');
      expect(status.files.single.path, 'a b.txt');
      expect(status.files.single.staged, GitChangeKind.added);
    });

    test('each conflict code maps to its kind', () {
      String line(String xy) =>
          'u $xy N... 100644 100644 100644 100644 a b c f\x00';
      expect(
        {
          for (final xy in ['DD', 'AU', 'UD', 'UA', 'DU', 'AA', 'UU'])
            xy: parseGitStatus(line(xy)).files.single.conflict,
        },
        {
          'DD': GitConflictKind.bothDeleted,
          'AU': GitConflictKind.addedByUs,
          'UD': GitConflictKind.deletedByThem,
          'UA': GitConflictKind.addedByThem,
          'DU': GitConflictKind.deletedByUs,
          'AA': GitConflictKind.bothAdded,
          'UU': GitConflictKind.bothModified,
        },
      );
    });
  });

  group('numstat', () {
    test('binary files and renames in -z form', () {
      final index = parseGitNumstat(fx.numstatIndex);
      expect(index, hasLength(2));
      expect(index[0].path, 'img.bin');
      expect(index[0].binary, isTrue);
      expect(index[1].path, 'new näme ✓.txt');
      expect(index[1].originalPath, 'old name.txt');
      expect(index[1].added, 0);
      final work = parseGitNumstat(fx.numstatWork).single;
      expect((work.path, work.added, work.deleted), ('keep.txt', 3, 0));
    });

    test('counts join the status rows they belong to', () {
      final status = withGitNumstat(
        parseGitStatus(fx.statusRename),
        unstaged: parseGitNumstat(fx.numstatWork),
        staged: parseGitNumstat(fx.numstatIndex),
      );
      final byPath = {for (final f in status.files) f.path: f};
      expect(byPath['keep.txt']!.addedLines, 3);
      expect(byPath['keep.txt']!.totalAdded, 3);
      expect(byPath['img.bin']!.binary, isTrue);
      expect(byPath['new näme ✓.txt']!.stagedAddedLines, 0);
      expect(byPath['untracked file é.md']!.totalAdded, isNull);
    });
  });

  test('log: commits, parents, decorations and a unicode subject', () {
    final commits = parseGitLog(fx.log);
    expect(commits, hasLength(2));
    expect(commits[0].subject, 'second: rename ✓');
    expect(commits[0].shortId, '97f3f68');
    expect(commits[0].refs, ['HEAD -> main']);
    expect(commits[0].parents, hasLength(1));
    expect(commits[0].authorName, 'Test User');
    expect(
      commits[0].time,
      DateTime.fromMillisecondsSinceEpoch(1792357278000, isUtc: true),
    );
    expect(commits[1].parents, isEmpty);
    expect(commits[1].refs, ['origin/main']);
  });

  test('branches: local with tracking, remote, current', () {
    final parsed = parseGitBranches(fx.branches);
    final main = parsed.local.single;
    expect(main.name, 'main');
    expect(main.current, isTrue);
    expect(main.upstream, 'origin/main');
    expect(main.ahead, 1);
    expect(main.behind, 0);
    expect(parsed.current, same(main));
    final remote = parsed.remote.single;
    expect(remote.name, 'origin/main');
    expect(remote.remoteName, 'origin');
    expect(remote.localName, 'main');
    expect(parsed.remoteOnly, isEmpty);
  });

  test('branches: origin/HEAD is skipped, gone and behind are read', () {
    const out =
        'refs/heads/old\x1fabc\x1forigin/old\x1fgone\x1f \x1f1\x1fs\n'
        'refs/heads/dev\x1fdef\x1forigin/dev\x1fahead 2, behind 3\x1f \x1f1\x1fs\n'
        'refs/remotes/origin/HEAD\x1fabc\x1f\x1f\x1f \x1f1\x1fs\n'
        'refs/remotes/origin/feature/x\x1fabc\x1f\x1f\x1f \x1f1\x1fs\n';
    final parsed = parseGitBranches(out);
    expect(parsed.local[0].upstreamGone, isTrue);
    expect((parsed.local[1].ahead, parsed.local[1].behind), (2, 3));
    expect(parsed.remote.map((b) => b.name), ['origin/feature/x']);
    expect(parsed.remoteOnly.single.localName, 'feature/x');
  });

  test('operation markers', () {
    expect(parseGitOperation(''), GitOperation.none);
    expect(parseGitOperation('MERGE_HEAD\n'), GitOperation.merge);
    expect(parseGitOperation('rebase-merge\n'), GitOperation.rebase);
    expect(parseGitOperation('CHERRY_PICK_HEAD\n'), GitOperation.cherryPick);
  });

  test('remotes keep only the name and the kind of host', () {
    final remotes = parseGitRemotes(
      'remote.origin.url git@github.com:o/r.git\n'
      'remote.mirror.url https://github.com/o/r.git\n'
      'remote.lab.url https://gitlab.com/o/r.git\n',
    );
    expect(remotes.map((r) => (r.name, r.kind)), [
      ('origin', GitRemoteKind.gitHubSsh),
      ('mirror', GitRemoteKind.gitHubHttps),
      ('lab', GitRemoteKind.other),
    ]);
  });

  group('error classification from real stderr', () {
    test('typed states, not errors', () {
      expect(
        classifyGitError(fx.notRepositoryError),
        GitProblem.notARepository,
      );
      expect(gitSaysNoCommitsYet(fx.logUnbornError), isTrue);
    });

    test('pull and push', () {
      expect(
        classifyGitError(fx.pullCannotFastForwardError),
        GitProblem.cannotFastForward,
      );
      expect(classifyGitError(fx.pushRejectedError), GitProblem.pushRejected);
    });

    test('sign-in: who rejected what', () {
      expect(classifyGitError(fx.httpsAuthError), GitProblem.authRequired);
      expect(
        classifyGitError(fx.httpsAuthError, usedGitHubToken: true),
        GitProblem.gitHubTokenRejected,
      );
      expect(classifyGitError(fx.noPromptError), GitProblem.authRequired);
      expect(
        classifyGitError(fx.sshAuthError, usedGitHubToken: true),
        GitProblem.authRequired,
      );
      expect(classifyGitError(fx.permissionError), GitProblem.noPermission);
    });

    test('commit identity', () {
      expect(classifyGitError(fx.identityError), GitProblem.identityMissing);
    });

    test('scrubbing masks the token and URL user info', () {
      const token = 'gho_FAKE0123456789abcdefFAKE';
      final out = scrubGitText(
        'x $token y https://user:$token@github.com/o/r.git',
        [token],
      );
      expect(out, isNot(contains(token)));
      expect(out, isNot(contains('user:')));
    });
  });
}
