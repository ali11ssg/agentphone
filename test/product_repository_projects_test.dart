import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/domain/models.dart';

void main() {
  test('configured providers retain OpenCode model variant metadata', () {
    final response = ProvidersResponse.fromJson({
      'providers': [
        {
          'id': 'provider',
          'name': 'Provider',
          'models': {
            'model': {
              'name': 'Model',
              'variants': {
                'fast': {'reasoningEffort': 'low'},
              },
            },
          },
        },
      ],
      'default': {'provider': 'model'},
    });

    expect(
      response.providers.single.modelData['model']?['variants'],
      contains('fast'),
    );
  });

  test('provider list keeps only connected providers in connection order', () {
    final response = ProvidersResponse.fromJson({
      'all': [
        {
          'id': 'opencode',
          'name': 'OpenCode Zen',
          'models': {'big-pickle': <String, Object?>{}},
        },
        {
          'id': 'zai-coding-plan',
          'name': 'Z.AI Coding Plan',
          'models': {
            'glm-5.2': {
              'variants': {
                'max': {'reasoningEffort': 'max'},
              },
            },
          },
        },
        {
          'id': 'unconnected',
          'name': 'Unconnected',
          'models': {'hidden-model': <String, Object?>{}},
        },
      ],
      'connected': ['zai-coding-plan', 'opencode'],
      'default': {
        'unconnected': 'hidden-model',
        'opencode': 'big-pickle',
        'zai-coding-plan': 'glm-5.2',
      },
    });

    expect(response.providers.map((provider) => provider.id), [
      'zai-coding-plan',
      'opencode',
    ]);
    expect(response.providers.first.modelIDs, ['glm-5.2']);
    expect(response.availableProviders.map((provider) => provider.id), [
      'opencode',
      'zai-coding-plan',
      'unconnected',
    ]);
    expect(response.defaultProviderID, 'zai-coding-plan');
    expect(response.defaultModelID, 'glm-5.2');
  });

  test('explicit empty connected list does not expose catalog-only models', () {
    final response = ProvidersResponse.fromJson({
      'all': [
        {
          'id': 'openai',
          'name': 'OpenAI',
          'models': {'gpt-5.6-sol': <String, Object?>{}},
        },
      ],
      'connected': <String>[],
      'default': {'openai': 'gpt-5.6-sol'},
    });

    expect(response.providers, isEmpty);
    expect(response.availableProviders.single.id, 'openai');
    expect(response.defaultProviderID, isNull);
    expect(response.defaultModelID, isNull);
  });

  test('project reference uses the upstream directory file-part contract', () {
    final attachment = PromptAttachment.reference(
      name: 'docs',
      path: '/workspace/../shared-docs',
    );

    expect(attachment.isDirectoryReference, isTrue);
    expect(attachment.toJson(), {
      'type': 'file',
      'mime': 'application/x-directory',
      'filename': 'docs',
      'url': 'file:///shared-docs',
    });
  });

  test('project reference preserves a remote Windows server path', () {
    final attachment = PromptAttachment.reference(
      name: 'platform-docs',
      path: r'C:\Shared Docs\platform',
    );

    expect(attachment.url, 'file:///C:/Shared%20Docs/platform');
    expect(attachment.isDirectoryReference, isTrue);
  });

  test('binary file content preserves metadata and decodes bytes', () {
    final content = FileContent.fromJson({
      'type': 'binary',
      'content': 'AAEC/w==',
      'encoding': 'base64',
      'mimeType': 'application/octet-stream',
    });

    expect(content.isBinary, isTrue);
    expect(content.encoding, 'base64');
    expect(content.mimeType, 'application/octet-stream');
    expect(content.bytes(), [0, 1, 2, 255]);
  });

  test('session parsing retains project and workspace ownership', () {
    final session = Session.fromJson({
      'id': 'session-1',
      'title': 'Mobile work',
      'projectID': 'project-1',
      'workspaceID': 'workspace-1',
      'directory': '/work/acme/packages/app',
      'path': 'packages/app',
      'time': {'created': 1, 'updated': 2},
    });

    expect(session.projectID, 'project-1');
    expect(session.workspaceID, 'workspace-1');
    expect(session.directory, '/work/acme/packages/app');
    expect(session.path, 'packages/app');
  });

  test('current OpenCode diff shape preserves patch and server counts', () {
    final diff = FileDiff.fromJson({
      'file': 'lib/main.dart',
      'patch': '@@ -1 +1 @@\n-old\n+new',
      'additions': 7,
      'deletions': 3,
      'status': 'modified',
    });

    expect(diff.patch, contains('+new'));
    expect(diff.counts, (added: 7, removed: 3));
    expect(diff.status, 'modified');
  });
}
