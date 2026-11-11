// Regenerate deliberately:
//   tool/qa/vps_test.sh test/goldens/kit/kit_server_trust_golden_test.dart -- --update-goldens
// and look at every changed image before committing it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/ui/kit/kit_server_trust.dart';

import 'kit_gallery.dart';

Widget _warning({bool certificate = true}) => SingleChildScrollView(
  child: KitServerTrustBody(
    origin: certificate
        ? 'https://private.example:4099'
        : 'http://public.example:4098',
    fingerprintSha256: certificate
        ? '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
        : null,
    certificateChanged: certificate,
    validFrom: certificate ? DateTime(2026, 10, 1) : null,
    validTo: certificate ? DateTime(2027, 10, 1) : null,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadKitGalleryFonts);
  for (final light in [false, true]) {
    final mode = light ? 'light' : 'dark';
    for (final size in kitGallerySizes) {
      testWidgets('certificate review ${kitGallerySize(size)} $mode', (
        tester,
      ) async {
        await kitGalleryPart(
          tester,
          name: kitGalleryName(
            'kit_server_trust_certificate',
            size,
            light: light,
          ),
          size: size,
          light: light,
          child: _warning(),
        );
      });
      testWidgets('public HTTP warning ${kitGallerySize(size)} $mode', (
        tester,
      ) async {
        await kitGalleryPart(
          tester,
          name: kitGalleryName('kit_server_trust_http', size, light: light),
          size: size,
          light: light,
          child: _warning(certificate: false),
        );
      });
    }
    for (final size in kitGalleryScaledSizes) {
      testWidgets('certificate review text2 ${kitGallerySize(size)} $mode', (
        tester,
      ) async {
        await kitGalleryPart(
          tester,
          name: kitGalleryName(
            'kit_server_trust_certificate',
            size,
            light: light,
            text2: true,
          ),
          size: size,
          light: light,
          textScale: 2,
          child: _warning(),
        );
      });
    }
  }
}
