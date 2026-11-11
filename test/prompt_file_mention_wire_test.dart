import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/domain/models.dart';

PromptAttachment _file(String path) =>
    PromptAttachment.projectFile(directory: '/srv/app', relativePath: path);

void main() {
  test('a mentioned file retains its exact reference and range', () {
    const text = 'Explain @lib/server.dart please';
    final resolved = resolveFileMentions(text, [_file('lib/server.dart')]);

    expect(resolved, hasLength(1));
    final attachment = resolved.single;
    expect(attachment.mime, 'text/plain');
    expect(attachment.filename, 'server.dart');
    expect(attachment.url, 'file:///srv/app/lib/server.dart');
    expect(attachment.mentionText, '@lib/server.dart');
    expect(attachment.mentionStart, 8);
    expect(attachment.mentionEnd, 24);
    expect(
      text.substring(attachment.mentionStart!, attachment.mentionEnd!),
      '@lib/server.dart',
    );
  });

  test('a mention the person deleted before Send sends no file part', () {
    final resolved = resolveFileMentions('Explain it', [
      _file('lib/server.dart'),
    ]);
    expect(resolved, isEmpty);
  });

  test('a path that only starts like the mention does not count', () {
    expect(
      resolveFileMentions('see @lib/server.dartx', [_file('lib/server.dart')]),
      isEmpty,
    );
    expect(
      resolveFileMentions('mail a@lib/server.dart', [_file('lib/server.dart')]),
      isEmpty,
    );
  });

  test('other attachments pass through and an unranged file has no source', () {
    const photo = PromptAttachment(
      mime: 'image/png',
      filename: 'a.png',
      url: 'data:image/png;base64,AA==',
    );
    expect(resolveFileMentions('hi', [photo]), [photo]);
    expect(_file('a.dart').toJson().containsKey('source'), isFalse);
  });
}
