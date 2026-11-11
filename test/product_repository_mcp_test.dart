import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/domain/product_repository.dart';

void main() {
  test('MCP drafts fail closed on unsafe transport data', () {
    for (final draft in [
      const McpServerDraft(
        name: 'remote',
        kind: McpServerKind.remote,
        url: 'ftp://mcp.example.com',
      ),
      const McpServerDraft(
        name: 'header',
        kind: McpServerKind.remote,
        url: 'https://mcp.example.com',
        headers: {'Authorization\nInjected': 'secret'},
      ),
      const McpServerDraft(name: 'local', kind: McpServerKind.local),
      const McpServerDraft(
        name: 'timeout',
        kind: McpServerKind.local,
        command: ['server'],
        timeoutMs: 0,
      ),
    ]) {
      expect(draft.toConfigJson, throwsA(isA<ProductException>()));
    }
  });
}
