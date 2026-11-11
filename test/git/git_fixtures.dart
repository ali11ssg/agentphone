// Output of real `git` 2.43 runs (LC_ALL=C), captured byte for byte from a
// throwaway repository: a staged rename to a unicode name with spaces, a
// staged binary file, an unstaged edit, an untracked file, a merge conflict,
// a detached HEAD, a branch without upstream and an unborn branch.

const statusRename =
    '# branch.oid b196b9f452aac7110d9a5277edd4d698e72d9872\x00# branch.head main\x00# branch.upstream origin/main\x00# branch.ab +0 -0\x001 M. N... 100644 100644 100644 87ae6b695deceaf160611414f7dcd5c7366b2e79 db6a79fd291d8d419791364f80a7101ae6425bd9 img.bin\x001 .M N... 100644 100644 100644 587be6b4c3f93f93c489c0111bba5596147a26cb 587be6b4c3f93f93c489c0111bba5596147a26cb keep.txt\x002 R. N... 100644 100644 100644 de980441c3ab03a8c07dda1ad27b8a11f39deb1e de980441c3ab03a8c07dda1ad27b8a11f39deb1e R100 new näme ✓.txt\x00old name.txt\x00? untracked file é.md\x00';

const numstatWork = '3\t0\tkeep.txt\x00';

const numstatIndex =
    '-\t-\timg.bin\x000\t0\t\x00old name.txt\x00new näme ✓.txt\x00';

const statusConflict =
    '# branch.oid 3a14ec50e8f2e5176f3ffcd80dc381fceeff728d\x00# branch.head main\x00# branch.upstream origin/main\x00# branch.ab +1 -0\x00u UU N... 100644 100644 100644 100644 74377959ac5a323f34122043b694d786be25af09 577b1bae9d5574155dc4fde03bc954442e3f5225 d6c03cf539f4777d6541aca4eee1cf523fa11a27 keep.txt\x00? untracked file é.md\x00';

const statusDetached =
    '# branch.oid 97f3f68369f647b29a7d0f89c9a65d1d93303a54\x00# branch.head (detached)\x00? untracked file é.md\x00';

const statusNoUpstream =
    '# branch.oid 3a14ec50e8f2e5176f3ffcd80dc381fceeff728d\x00# branch.head lonely\x00? untracked file é.md\x00';

const statusUnborn =
    '# branch.oid (initial)\x00# branch.head main\x001 A. N... 000000 100644 100644 0000000000000000000000000000000000000000 c1b0730e0133447badcfd47fd144e254807b06e1 a b.txt\x00';

const log =
    '97f3f68369f647b29a7d0f89c9a65d1d93303a54\x1f97f3f68\x1fTest User\x1ft@example.com\x1f1792357278\x1fb196b9f452aac7110d9a5277edd4d698e72d9872\x1fHEAD -> main\x1fsecond: rename ✓\x00b196b9f452aac7110d9a5277edd4d698e72d9872\x1fb196b9f\x1fTest User\x1ft@example.com\x1f1792357277\x1f\x1forigin/main\x1ffirst commit\x00';

const branches =
    'refs/heads/main\x1f97f3f68\x1forigin/main\x1fahead 1\x1f*\x1f1792357278\x1fsecond: rename ✓\nrefs/remotes/origin/main\x1fb196b9f\x1f\x1f\x1f \x1f1792357277\x1ffirst commit\n';

const logUnbornError =
    'fatal: your current branch \'main\' does not have any commits yet\n';

const notRepositoryError =
    'fatal: not a git repository (or any parent up to mount point /home/user)\nStopping at filesystem boundary (GIT_DISCOVERY_ACROSS_FILESYSTEM not set).\n';

const pullCannotFastForwardError =
    'From ../remote\n   97f3f68..0b91a93  main       -> origin/main\nhint: Diverging branches can\'t be fast-forwarded, you need to either:\nhint: \nhint: \tgit merge --no-ff\nhint: \nhint: or:\nhint: \nhint: \tgit rebase\nhint: \nhint: Disable this message with "git config advice.diverging false"\nfatal: Not possible to fast-forward, aborting.\n';

const pushRejectedError =
    'To ../remote.git\n ! [rejected]        main -> main (fetch first)\nerror: failed to push some refs to \'../remote.git\'\nhint: Updates were rejected because the remote contains work that you do not\nhint: have locally. This is usually caused by another repository pushing to\nhint: the same ref. If you want to integrate the remote changes, use\nhint: \'git pull\' before pushing again.\nhint: See the \'Note about fast-forwards\' in \'git push --help\' for details.\n';

const httpsAuthError =
    "remote: Invalid username or token. Password authentication is not supported for Git operations.\nfatal: Authentication failed for 'https://github.com/o/r.git/'\n";

const noPromptError =
    "fatal: could not read Username for 'https://github.com': terminal prompts disabled\n";

const sshAuthError =
    'git@github.com: Permission denied (publickey).\nfatal: Could not read from remote repository.\n\nPlease make sure you have the correct access rights\nand the repository exists.\n';

const permissionError =
    "remote: Permission to o/r.git denied to someone.\nfatal: unable to access 'https://github.com/o/r.git/': The requested URL returned error: 403\n";

const identityError =
    'Author identity unknown\n\n*** Please tell me who you are.\n\nRun\n\n  git config --global user.email "you@example.com"\n';
