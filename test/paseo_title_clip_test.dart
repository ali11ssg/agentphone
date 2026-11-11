// Paseo cuts a new agent's title from the first prompt at 60 characters with
// no sign of it; the header must show that cut as an ellipsis.
import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/paseo/mappers.dart';

String _title(String title) => paseoSession({
  'id': 'a1',
  'cwd': '/p',
  'provider': 'claude',
  'title': title,
}).title!;

void main() {
  const prompt =
      'Build a tip calculator in one index.html: bill amount, 10, 15 and 20';

  test('a first prompt cut at 60 characters ends with an ellipsis', () {
    final cut = prompt.substring(0, 60).trim();
    expect(cut.length, greaterThanOrEqualTo(58));
    expect(_title(cut), '$cut…');
  });

  test('a finished sentence and a short title stay as they are', () {
    const sentence = 'Build a tip calculator in index.html with a bill split.';
    expect(_title(sentence), sentence);
    expect(_title('Tip calculator'), 'Tip calculator');
  });
}
