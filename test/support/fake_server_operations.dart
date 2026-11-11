import 'package:agentphone/domain/product_repository.dart';

/// In-memory operations fixture paired with a synthetic server gateway.
class FakeServerOperations extends ProductRepository {
  FakeServerOperations([ServerGateway? gateway]);
  @override
  void setLocation({String? directory, String? workspace}) {}
  @override
  Future<ChatDefaults> loadChatDefaults() async => const ChatDefaults();
  @override
  Future<List<PendingQuestion>> listQuestions() async => const [];
  @override
  Future<CatalogSnapshot> loadCatalog() async =>
      const CatalogSnapshot(providers: [], models: [], agents: []);
  @override
  Future<List<IntegrationInfo>> listIntegrations() async => const [];
  @override
  Future<List<WorkspaceProject>> listProjects() async => const [];
  @override
  Future<List<WorkspaceInfo>> listWorkspaces() async => const [];
  @override
  Future<List<CommandInfo>> listCommands() async => const [];
  @override
  Future<List<SkillInfo>> listSkills() async => const [];
  @override
  Future<List<ReferenceInfo>> listReferences() async => const [];
  @override
  Future<ServerPage<GlobalSessionResult>> listGlobalSessions({
    String? search,
    bool includeArchived = false,
    String? cursor,
    int limit = 50,
  }) async => const ServerPage(items: []);
  @override
  Future<List<SavedPermission>> listSavedPermissions() async => const [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
