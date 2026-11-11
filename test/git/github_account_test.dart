import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/domain/git/github_device_flow.dart';
import 'package:agentphone/state/github_account.dart';
import 'package:agentphone/state/profiles.dart';
import 'package:agentphone/ui/kit/kit_redact.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'git_test_support.dart';

/// Device flow with scripted answers.
class _Flow extends GitHubDeviceFlow {
  _Flow();

  Completer<GitHubCredential>? poll;
  Object? codeError;
  String login = 'octocat';
  int refreshes = 0;
  Object? refreshError;

  @override
  Future<GitHubDeviceCode> requestCode({String scope = gitHubScope}) async {
    if (codeError != null) throw codeError!;
    return GitHubDeviceCode(
      deviceCode: 'dc_fake',
      userCode: 'WDJB-MJHT',
      verificationUri: Uri.parse('https://github.com/login/device'),
      expiresAt: DateTime.utc(2026, 10, 19, 3),
      interval: const Duration(seconds: 5),
    );
  }

  @override
  Future<GitHubCredential> pollForToken(
    GitHubDeviceCode code, {
    bool Function()? cancelled,
  }) {
    poll = Completer<GitHubCredential>();
    return poll!.future;
  }

  @override
  Future<String> fetchLogin(String token) async => login;

  @override
  Future<GitHubCredential> refresh(GitHubCredential current) async {
    refreshes++;
    if (refreshError != null) throw refreshError!;
    return GitHubCredential(
      accessToken: 'ghu_refreshed0123456789',
      login: current.login,
      refreshToken: 'ghr_refreshed0123456789',
      expiresAt: DateTime.utc(2026, 10, 20),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, String> secure;
  const profileId = 'builtin';
  const key = 'oc.githubToken.$profileId';

  setUp(() {
    secure = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async {
            final args = (call.arguments as Map).cast<String, Object?>();
            switch (call.method) {
              case 'read':
                return secure[args['key']];
              case 'write':
                secure[args['key']! as String] = args['value']! as String;
                return null;
              case 'delete':
                secure.remove(args['key']);
                return null;
              case 'readAll':
                return secure;
            }
            return null;
          },
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('oc/background'),
          (_) async => null,
        );
  });

  GitHubAccountController controller(_Flow flow, {DateTime? now}) =>
      GitHubAccountController(
        profileId: profileId,
        store: GitHubTokenStore(secure: const FlutterSecureStorage()),
        flow: flow,
        now: () => now ?? DateTime.utc(2026, 10, 19, 2),
      );

  test('sign-in walks the states and stores the token under the key', () async {
    final flow = _Flow();
    final account = controller(flow);
    await account.load();
    expect(account.state, isA<GitHubSignedOut>());

    final states = <GitHubSignInState>[];
    account.addListener(() => states.add(account.state));
    final done = account.startSignIn();
    await Future<void>.delayed(Duration.zero);
    final waiting = account.state as GitHubAwaitingUser;
    expect(waiting.userCode, 'WDJB-MJHT');
    expect(waiting.verificationUri.host, 'github.com');

    flow.poll!.complete(const GitHubCredential(accessToken: fakeGitHubToken));
    await done;
    expect((account.state as GitHubSignedIn).login, 'octocat');
    expect(states.map((s) => s.runtimeType), [
      GitHubRequestingCode,
      GitHubAwaitingUser,
      GitHubFinishing,
      GitHubSignedIn,
    ]);
    expect(secure.keys, [key]);
    expect(secure[key], contains(fakeGitHubToken));
    expect(
      KitRedact.text('token $fakeGitHubToken'),
      isNot(contains(fakeGitHubToken)),
    );
    expect(await account.tokenForGit(), fakeGitHubToken);
  });

  test('a failed attempt says why and stores nothing', () async {
    final flow = _Flow()
      ..codeError = const GitHubSignInException(
        GitHubSignInProblem.deviceFlowDisabled,
      );
    final account = controller(flow);
    await account.startSignIn();
    expect(
      (account.state as GitHubSignedOut).problem,
      GitHubSignInProblem.deviceFlowDisabled,
    );
    expect(secure, isEmpty);
  });

  test('cancel while waiting ignores a late token', () async {
    final flow = _Flow();
    final account = controller(flow);
    await account.load();
    final done = account.startSignIn();
    await Future<void>.delayed(Duration.zero);
    account.cancelSignIn();
    expect(account.state, isA<GitHubSignedOut>());
    flow.poll!.complete(const GitHubCredential(accessToken: fakeGitHubToken));
    await done;
    expect(account.state, isA<GitHubSignedOut>());
    expect(secure, isEmpty);
  });

  test('sign-out and a rejected token both forget it', () async {
    await GitHubTokenStore().write(
      profileId,
      const GitHubCredential(accessToken: fakeGitHubToken, login: 'octocat'),
    );
    final account = controller(_Flow());
    await account.load();
    expect((account.state as GitHubSignedIn).login, 'octocat');
    await account.tokenRejected();
    expect(
      (account.state as GitHubSignedOut).problem,
      GitHubSignInProblem.tokenRejected,
    );
    expect(secure, isEmpty);
    expect(await account.tokenForGit(), isNull);

    await GitHubTokenStore().write(
      profileId,
      const GitHubCredential(accessToken: fakeGitHubToken, login: 'octocat'),
    );
    await account.load();
    await account.signOut();
    expect(secure, isEmpty);
  });

  test('an expired token is refreshed first and the new pair stored', () async {
    await GitHubTokenStore().write(
      profileId,
      GitHubCredential(
        accessToken: 'ghu_old0123456789abc',
        login: 'octocat',
        refreshToken: 'ghr_old0123456789abc',
        expiresAt: DateTime.utc(2026, 10, 19, 1),
      ),
    );
    final flow = _Flow();
    final account = controller(flow);
    await account.load();
    expect(await account.tokenForGit(), 'ghu_refreshed0123456789');
    expect(flow.refreshes, 1);
    expect(secure[key], contains('ghu_refreshed0123456789'));
  });

  group('deletion sweep', () {
    Future<ProfileStore> store() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      return ProfileStore(prefs: prefs, secure: const FlutterSecureStorage());
    }

    test('removing the profile deletes its GitHub sign-in', () async {
      final profiles = await store();
      await GitHubTokenStore().write(
        profileId,
        const GitHubCredential(accessToken: fakeGitHubToken),
      );
      await GitHubTokenStore().write(
        'other',
        const GitHubCredential(accessToken: '${fakeGitHubToken}2'),
      );
      expect(GitHubTokenStore.keyFor(profileId), key);
      await profiles.remove(profileId);
      expect(secure.keys, isNot(contains(key)));
      expect(secure.keys, contains('oc.githubToken.other'));
    });

    test('the saved sign-ins reset deletes every GitHub sign-in', () async {
      final profiles = await store();
      await GitHubTokenStore().write(
        profileId,
        const GitHubCredential(accessToken: fakeGitHubToken),
      );
      await profiles.resetSavedSignIns();
      expect(
        secure.keys.where((k) => k.startsWith('oc.githubToken.')),
        isEmpty,
      );
    });
  });
}
