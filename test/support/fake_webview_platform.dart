// A stand-in for the platform web view, so the preview's real
// `WebViewController` code runs in widget tests: it records what the app asked
// the page to do and lets a test play the page (navigate, finish, fail).
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

class FakeWebViewPlatform extends WebViewPlatform {
  FakeController? controller;
  FakeNavigationDelegate? delegate;
  int cookieClears = 0;

  /// Installs the fake and returns it; call from `setUp`.
  static FakeWebViewPlatform install() {
    final platform = FakeWebViewPlatform();
    WebViewPlatform.instance = platform;
    return platform;
  }

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) => controller = FakeController(params);

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => delegate = FakeNavigationDelegate(params);

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => FakeWidget(params);

  @override
  PlatformWebViewCookieManager createPlatformCookieManager(
    PlatformWebViewCookieManagerCreationParams params,
  ) => FakeCookies(params, this);
}

class FakeController extends PlatformWebViewController {
  FakeController(super.params) : super.implementation();

  final loaded = <Uri>[];
  int reloads = 0;
  int cacheClears = 0;
  int storageClears = 0;
  bool history = false;
  int backs = 0;
  JavaScriptMode? javaScript;
  final channels = <String>[];

  @override
  Future<void> loadRequest(LoadRequestParams params) async =>
      loaded.add(params.uri);

  @override
  Future<void> reload() async => reloads++;

  @override
  Future<bool> canGoBack() async => history;

  @override
  Future<void> goBack() async => backs++;

  @override
  Future<void> clearCache() async => cacheClears++;

  @override
  Future<void> clearLocalStorage() async => storageClears++;

  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async =>
      javaScript = mode;

  @override
  Future<void> addJavaScriptChannel(
    JavaScriptChannelParams javaScriptChannelParams,
  ) async => channels.add(javaScriptChannelParams.name);

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {}
}

class FakeNavigationDelegate extends PlatformNavigationDelegate {
  FakeNavigationDelegate(super.params) : super.implementation();

  NavigationRequestCallback? onRequest;
  PageEventCallback? onStarted;
  PageEventCallback? onFinished;
  WebResourceErrorCallback? onError;
  UrlChangeCallback? onUrl;

  @override
  Future<void> setOnNavigationRequest(NavigationRequestCallback cb) async =>
      onRequest = cb;

  @override
  Future<void> setOnPageStarted(PageEventCallback cb) async => onStarted = cb;

  @override
  Future<void> setOnPageFinished(PageEventCallback cb) async => onFinished = cb;

  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback cb) async =>
      onError = cb;

  @override
  Future<void> setOnUrlChange(UrlChangeCallback cb) async => onUrl = cb;

  @override
  Future<void> setOnProgress(ProgressCallback cb) async {}

  @override
  Future<void> setOnHttpError(HttpResponseErrorCallback cb) async {}

  @override
  Future<void> setOnHttpAuthRequest(HttpAuthRequestCallback cb) async {}

  @override
  Future<void> setOnSSlAuthError(SslAuthErrorCallback cb) async {}

  /// What the page asks: a main-frame (or sub-frame) navigation.
  FutureOr<NavigationDecision> navigate(String url, {bool mainFrame = true}) =>
      onRequest!(NavigationRequest(url: url, isMainFrame: mainFrame));
}

class FakeWidget extends PlatformWebViewWidget {
  FakeWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) =>
      const SizedBox.expand(key: ValueKey('fake-web-view'));
}

class FakeCookies extends PlatformWebViewCookieManager {
  FakeCookies(super.params, this.owner) : super.implementation();
  final FakeWebViewPlatform owner;

  @override
  Future<bool> clearCookies() async {
    owner.cookieClears++;
    return true;
  }
}
