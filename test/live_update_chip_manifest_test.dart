// AgentPhone does not promote its notification into a status bar chip.
//
// Android 16 QPR1+ can promote a notification when the app asks for it, and
// the asking needs a permission the fork does not want to hold: a promoted
// notification is a permanent presence on the screen. The fork therefore
// never asks, never declares the permission, and the notification stays an
// ordinary one.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the manifest does not ask for the promoted-notification permission', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(
      manifest,
      isNot(contains('android.permission.POST_PROMOTED_NOTIFICATIONS')),
    );
  });

  test('the renderer never asks the system to promote the notification', () {
    final renderer = File(
      'android/app/src/main/kotlin/io/github/agentphone/app/StatusNotificationRenderer.kt',
    ).readAsStringSync();
    expect(renderer, contains('setRequestPromotedOngoing(false)'));
    expect(renderer, isNot(contains('setRequestPromotedOngoing(true)')));
  });
}
