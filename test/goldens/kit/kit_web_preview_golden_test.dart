// Gallery (gate G4) for KitWebPreview (TEST-9): the page area at 412x915 and
// 1280x800, dark and light, and the error state (nothing answers) at 412x915,
// dark and light, and at 2.0 text. The platform web view is the test fake
// (test/support/fake_webview_platform.dart): a blank page.
//
// Regenerate deliberately:
//   flutter test --update-goldens test/goldens/kit/kit_web_preview_golden_test.dart
// and look at every changed image before committing it.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/ui/kit/kit.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import '../../support/fake_webview_platform.dart';
import 'kit_gallery.dart';

const _states = Size(412, 915);
final _origin = Uri.parse('http://127.0.0.1:5173/');

/// A [KitWebPreview] that, when [fail], is told by the (fake) page that
/// nothing answered once it has started.
class _Page extends StatefulWidget {
  const _Page({required this.platform, required this.fail});
  final FakeWebViewPlatform platform;
  final bool fail;

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  final _controller = KitWebPreviewController();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.fail) {
      _timer = Timer(const Duration(milliseconds: 20), () {
        widget.platform.delegate?.onError?.call(
          const WebResourceError(
            errorCode: -6,
            description: 'refused',
            isForMainFrame: true,
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 360,
    height: 480,
    child: KitWebPreview(
      origin: _origin,
      controller: _controller,
      supported: true,
      onLeave: (_) {},
    ),
  );
}

void main() {
  setUpAll(loadKitGalleryFonts);
  late FakeWebViewPlatform platform;
  setUp(() => platform = FakeWebViewPlatform.install());

  group('KitWebPreview', () {
    for (final light in [false, true]) {
      final mode = light ? 'light' : 'dark';

      testWidgets('error · 412x915 · $mode', (tester) async {
        await kitGalleryPart(
          tester,
          name: kitGalleryName('kit_web_preview_error', _states, light: light),
          size: _states,
          light: light,
          child: _Page(platform: platform, fail: true),
        );
      });

      for (final size in [_states, const Size(1280, 800)]) {
        testWidgets('page · ${kitGallerySize(size)} · $mode', (tester) async {
          await kitGalleryPart(
            tester,
            name: kitGalleryName('kit_web_preview_page', size, light: light),
            size: size,
            light: light,
            child: _Page(platform: platform, fail: false),
          );
        });
      }
    }

    for (final size in kitGalleryScaledSizes) {
      testWidgets('error · 2.0 text · ${kitGallerySize(size)} · dark', (
        tester,
      ) async {
        await kitGalleryPart(
          tester,
          name: kitGalleryName(
            'kit_web_preview_error',
            size,
            light: false,
            text2: true,
          ),
          size: size,
          light: false,
          textScale: 2,
          child: _Page(platform: platform, fail: true),
        );
      });
    }
  });
}
