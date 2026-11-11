/// Which permission requests must always ask the person.
///
/// AgentPhone answers a permission automatically only when the person chose
/// automatic approval for that conversation. These rules are stricter: some
/// commands are never answered by the phone, whatever the mode says, because
/// the cost of asking once is much lower than the cost of a surprise.
///
/// Always asks:
///  - `sudo`, a recursive delete, a permission or ownership change, a disk
///    write, a force push;
///  - a package install (apt, npm, pip, cargo, gem, pub, brew);
///  - a network download (curl, wget);
///  - a write to a path outside the project folder.
library;

import 'models.dart';

/// Command prefixes that always need a person.
const List<String> kRiskyCommandPrefixes = <String>[
  'sudo',
  'su ',
  'rm -rf',
  'rm -fr',
  'rm -r ',
  'chmod 777',
  'chmod -R',
  'chown',
  'chgrp',
  'mkfs',
  'dd if=',
  'shutdown',
  'reboot',
  'git push',
  'git reset --hard',
  'git clean -fd',
  'npm publish',
  'npm install',
  'yarn add',
  'pnpm add',
  'pip install',
  'pip3 install',
  'gem install',
  'cargo install',
  'flutter pub add',
  'dart pub add',
  'apt install',
  'apt-get install',
  'apk add',
  'brew install',
  'curl',
  'wget',
];

/// Folders a write outside the project folder lands in.
const List<String> kSystemWritePrefixes = <String>[
  '/etc',
  '/usr',
  '/bin',
  '/sbin',
  '/lib',
  '/var',
  '/boot',
  '/root',
  '/system',
  '/data',
];

/// Whether a command line is one of the risky ones.
bool isRiskyCommand(String command) {
  final line = command.trimLeft().toLowerCase();
  if (line.isEmpty) return false;
  for (final prefix in kRiskyCommandPrefixes) {
    if (line.startsWith(prefix)) return true;
  }
  // A risky word anywhere in a chain counts too: `cd /tmp && rm -rf x`.
  for (final word in ['rm -rf', 'sudo ', 'git push --force', '--force-with-lease']) {
    if (line.contains(word)) return true;
  }
  // A write into a system folder.
  for (final folder in kSystemWritePrefixes) {
    if (line.contains(' $folder/') || line.contains(' $folder ')) return true;
  }
  return false;
}

/// Whether a path points outside the project folder.
bool isOutsideProject(String path) {
  final value = path.trim();
  if (value.isEmpty) return false;
  if (value.startsWith('/')) return true;
  if (value.startsWith('~')) return true;
  if (value.contains('../')) return true;
  return false;
}

/// Whether this request must always be answered by a person.
bool isRiskyPermission(PermissionRequest permission) {
  final kind = permission.permission.toLowerCase();
  final patterns = permission.patterns;

  if (kind == 'bash' ||
      kind == 'shell' ||
      kind == 'run' ||
      kind == 'terminal') {
    return patterns.any((pattern) => isRiskyCommand(pattern));
  }
  if (kind == 'edit' ||
      kind == 'write' ||
      kind == 'patch' ||
      kind == 'apply_patch') {
    return patterns.any(isOutsideProject);
  }
  if (kind.contains('download') || kind.contains('install')) return true;
  return false;
}
