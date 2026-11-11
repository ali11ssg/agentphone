import 'package:agentphone/domain/models.dart';
import 'fake_server_gateway.dart';
import 'package:agentphone/domain/server_gateway.dart';

/// Existing non-pagination fixtures expose their transcript as one complete
/// chronological page. Pagination-specific fakes override messagePage directly.
mixin CompleteMessageHistory on FakeServerGateway {
  // These compatibility fixtures model transcript reads, not receipt sends.
  // Receipt-specific fakes explicitly opt into the capability and implement
  // promptWithMessageID, so inherited production HTTP never runs in a fake.
  @override
  ServerCapabilities get capabilities => const ServerCapabilities(
    clientPromptMessageID: true,
    setupConfigRead: true,
    setupMcpInventory: true,
  );
  // Fixtures override this with their transcript. An empty default prevents
  // falling back into FakeServerGateway.messages -> messagePage -> messages.
  @override
  Future<List<MessageWithParts>> messages(String id) async => const [];

  @override
  Future<ServerPage<MessageWithParts>> messagePage(
    String id, {
    String? cursor,
    int limit = 100,
  }) async => ServerPage(items: cursor == null ? await messages(id) : const []);
}
