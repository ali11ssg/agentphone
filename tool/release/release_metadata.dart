/// Reads the app's full release identity, including its Android build number.
String? releaseVersionFromPubspec(String pubspec) {
  final match = RegExp(
    r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+\+[0-9]+)\s*(?:#.*)?$',
    multiLine: true,
  ).firstMatch(pubspec);
  return match?.group(1);
}

/// Returns actionable discrepancies between the three release metadata files.
///
/// After an optional Unreleased section, the first heading names the release. The
/// versioned release notes must start with the exact public release header.
List<String> validateReleaseMetadata({
  required String pubspec,
  required String changelog,
  required String? releaseNotes,
}) {
  final version = releaseVersionFromPubspec(pubspec);
  if (version == null) {
    return ['pubspec.yaml must contain version: X.Y.Z+BUILD.'];
  }

  final issues = <String>[];
  final headings = RegExp(
    r'^## (.+)$',
    multiLine: true,
  ).allMatches(changelog).map((match) => match.group(1)!.trim()).toList();
  if (headings.isNotEmpty && headings.first == 'Unreleased') {
    headings.removeAt(0);
  }
  final topHeading = headings.isEmpty ? null : headings.first;
  final topVersion = topHeading == null
      ? null
      : RegExp(
          r'^([0-9]+\.[0-9]+\.[0-9]+\+[0-9]+)(?:\s|$)',
        ).firstMatch(topHeading)?.group(1);
  if (topVersion != version) {
    issues.add(
      'CHANGELOG.md first release heading must name $version '
      '(found ${topHeading ?? "no release heading"}).',
    );
  }

  final notesPath = 'docs/releases/v$version.md';
  if (releaseNotes == null) {
    issues.add('Add $notesPath with header # AgentPhone $version.');
  } else {
    final firstLine = releaseNotes.split('\n').first.trim();
    if (firstLine != '# AgentPhone $version') {
      issues.add('$notesPath must start with # AgentPhone $version.');
    }
  }
  return issues;
}
