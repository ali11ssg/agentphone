import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/domain/models.dart';
import 'fake_server_gateway.dart';
import 'package:agentphone/domain/product_repository.dart';
import 'fake_event_channel.dart';
import 'package:agentphone/state/connection.dart';
import 'package:agentphone/state/profiles.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TestApi extends FakeServerGateway {
  TestApi({this.files, this.findFiles, this.contents = const {}})
    : super(baseUrl: 'http://localhost');

  final Future<List<FileNode>> Function(String path)? files;
  final Future<List<String>> Function(String query)? findFiles;
  final Map<String, FileContent> contents;

  @override
  Future<List<FileNode>> listFiles([String path = '']) async =>
      files?.call(path) ?? const [];

  @override
  Future<List<String>> findFile(String query) async =>
      findFiles?.call(query) ?? const [];

  @override
  Future<FileContent> fileContent(String path) async => contents[path]!;

  @override
  Future<List<Session>> sessions() async => const [];

  @override
  Future<Map<String, String>> sessionStatuses() async => const {};
}

class LocationRepository
    implements ProductRepository, LocationAwareProductRepository {
  int _revision = 0;
  int terminalLoads = 0;
  CatalogSnapshot catalog = const CatalogSnapshot(
    providers: [],
    models: [],
    agents: [],
  );

  @override
  int get locationRevision => _revision;

  @override
  void setLocation({String? directory, String? workspace}) {
    _revision++;
  }

  @override
  Future<List<WorkspaceProject>> listProjects() async => const [];

  @override
  Future<List<WorkspaceInfo>> listWorkspaces() async => const [];

  @override
  Future<List<TerminalProcess>> listTerminals() async {
    terminalLoads++;
    return const [];
  }

  @override
  Future<CatalogSnapshot> loadCatalog() async => catalog;

  @override
  Future<List<VersionControlFile>> listFileStatuses() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class SignalController extends ConnectionController {
  SignalController(super.store);

  void signalLocation(ProductRepository value) {
    repository = value;
    locationRevision++;
    notifyListeners();
  }
}

Future<ConnectionController> regressionController({
  FakeServerGateway? api,
  ProductRepository? repository,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ConnectionController(ProfileStore(prefs: prefs))
    ..api = api ?? TestApi()
    ..repository = repository
    ..status = StreamStatus.connected;
}
