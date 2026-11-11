// A conversation that cannot start is kept for Report a problem: the words
// the person saw and, under them, the technical cause (owner's phone,
// 2026-10-17: nothing in the report said why a Claude Code chat failed).
import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/diagnostics/app_diagnostics.dart';
import 'package:agentphone/state/connection.dart';
import 'package:agentphone/state/profiles.dart';
import 'package:agentphone/ui/screens/chats/chats_host.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('a failed start is recorded in the app diagnostics', () async {
    SharedPreferences.setMockInitialValues({});
    final diagnostics = AppDiagnosticsController();
    addTearDown(diagnostics.dispose);
    final controller = ConnectionController(
      ProfileStore(prefs: await SharedPreferences.getInstance()),
      diagnostics: diagnostics,
    );
    addTearDown(controller.dispose);
    final host = ConnectionChatsHost(controller);

    // Not connected anywhere: the start fails.
    await expectLater(
      host.startChat('/root/projects/alpha', agentId: 'claude', prompt: 'hi'),
      throwsA(anything),
    );

    final entry = diagnostics.entries.single;
    expect(entry.source, 'chat.start');
    expect(entry.message, startsWith('Starting a chat with claude failed: '));
  });
}
