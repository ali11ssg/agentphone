// Families for files, changes, review, worktrees and undo:
//   oc2_files - the OpenCode 2 routes the same pages read: /api/fs/*, /api/vcs*,
//               /api/worktree and the staged undo's FileDiff.Info.
// Paseo's checkout, file and worktree messages are not read by the app at all
// (see lists_actions-style ledger files_actions_ledger.json).
import { familyBuilder } from '../oc_cases_lib.mjs';
import { only, none } from './models.mjs';

const f = (kind, values) => ({ kind, ...(values ? { values } : {}) });
const PATCH = '@@ -10,3 +10,4 @@\n-final total = sum;\n+final total = sum.roundToDouble();\n+log(total);';

export function oc2FilesFamily(contract) {
  const { schema, kase } = familyBuilder(contract, [
    { name: 'FileSystem.Entry' },
    { name: 'Vcs.Info' },
    { name: 'Vcs.FileStatus' },
    { name: 'FileDiff.Info' },
    { name: 'Worktree.Info' },
    { name: 'Session.Revert' },
  ]);
  const u = (use, g, v, o = {}) => use(g, v, { ...o, probes: only(v, o.probes ?? {}) });
  const cases = [];
  cases.push(kase('fs', (use) => [
    u(use, 'FileSystem.Entry', { path: 'lib/checkout', type: 'directory' }, { probes: { path: ['checkout'], type: [] } }),
    u(use, 'FileSystem.Entry', { path: 'lib/cart_total.dart', type: 'file' }, { probes: { path: ['cart_total.dart'], type: [] } }),
  ], { kind: 'fs' }));
  cases.push(kase('changes', (use) => ({
    info: u(use, 'Vcs.Info', { branch: { current: 'fix/cart-total', default: 'main' } }, { probes: { 'branch.current': ['fix/cart-total'], 'branch.default': ['main'] } }),
    status: [u(use, 'Vcs.FileStatus', { file: 'lib/cart_total.dart', additions: 17, deletions: 5, status: 'modified' }, { probes: { file: ['cart_total.dart'], additions: ['+17'], deletions: ['−5'], status: ['Modified'] } })],
    diff: [u(use, 'FileDiff.Info', { file: 'lib/cart_total.dart', patch: PATCH, additions: 17, deletions: 5, status: 'modified' }, { probes: { file: ['cart_total.dart'], patch: ['sum.roundToDouble()'], additions: ['+17'], deletions: ['−5'], status: ['Modified'] } })],
  }), { kind: 'changes' }));
  // The undo staged from a prompt: what the Review-the-undo page lists.
  cases.push(kase('undo_staged', (use) => u(use, 'Session.Revert', {
    messageID: 'msg_files_r1', partID: 'prt_files_r1', snapshot: 'snap_files1',
    files: [{ file: 'lib/cart_total.dart', patch: PATCH, additions: 17, deletions: 5, status: 'modified' }],
  }, { probes: { ...none('messageID', 'partID', 'snapshot', 'files[].status'), 'files[].file': ['cart_total.dart'], 'files[].patch': ['sum.roundToDouble()'], 'files[].additions': ['+17'], 'files[].deletions': ['−5'] } }), { kind: 'undo' }));
  cases.push(kase('worktree_created', (use) => u(use, 'Worktree.Info', { directory: '/work/shopfront-retry' }, { probes: { directory: ['shopfront-retry'] } }), { kind: 'worktree' }));
  return { schema, cases };
}
