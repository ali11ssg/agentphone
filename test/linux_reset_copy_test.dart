import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/l10n/app_localizations_en.dart';

void main() {
  test('the reset leftover sentence does not double the phone', () {
    final text = AppLocalizationsEn().linuxMgrResetForgetFailed('This phone');
    expect(
      RegExp('phone', caseSensitive: false).allMatches(text).length,
      1,
      reason: text,
    );
    expect(text, isNot(contains('Servers')), reason: 'setup re-creates it');
    expect(text, isNot(contains('could not be cleared')));
    final left = AppLocalizationsEn().linuxMgrResetLeft(
      'This phone',
      'its saved connection',
    );
    expect(RegExp('phone', caseSensitive: false).allMatches(left).length, 1);
  });
}
