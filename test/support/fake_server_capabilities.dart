import 'package:agentphone/domain/server_gateway.dart';

/// Synthetic feature-rich backend for protocol-neutral widget fixtures.
/// Production backend capabilities are tested through their real gateways.
const testServerCapabilities = ServerCapabilities(
  phoneTeamExecution: true,
  clientPromptMessageID: true,
  commandReceipts: true,
  setupConfigRead: true,
  setupMcpInventory: true,
  mcpRuntimeAdds: true,
  mcpChatConnect: true,
  mcpChatOAuth: true,
  mcpChatToolRefresh: true,
);
