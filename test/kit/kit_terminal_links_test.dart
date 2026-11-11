// OSC 52 clipboard writes and links that wrap over several terminal rows
// (the Claude Code sign-in URL that could not be copied).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/l10n/app_localizations.dart';
import 'package:agentphone/ui/app_theme.dart';
import 'package:agentphone/ui/kit/kit.dart';
import 'package:xterm/xterm.dart' as xterm;

import 'kit_motion_still.dart';

String _b64(String s) => base64.encode(utf8.encode(s));

const _url =
    'https://claude.com/cai/oauth/authorize?code=true&client_id=abc-123&'
    'response_type=code&redirect_uri=https%3A%2F%2Fexample.com%2Fcallback';

Future<void> _openLinkSheet(BuildContext context) =>
    showKitTerminalLinkSheet(context, _url);

void main() {
  kitMotionStillTests(
    'showKitTerminalLinkSheet',
    opens: {
      'default': KitMotionOpen(_openLinkSheet, shows: 'Link in the terminal'),
    },
    changes: {
      'dismissed': kitModalDismiss(
        _openLinkSheet,
        shows: 'Link in the terminal',
      ),
    },
  );

  group('OSC 52 parse', () {
    test('a set-clipboard write decodes', () {
      expect(KitTerminalOsc52.parse(['c', _b64('héllo $_url')]), 'héllo $_url');
    });

    test('a query is never answered', () {
      expect(KitTerminalOsc52.parse(['c', '?']), isNull);
    });

    test('an oversize payload is ignored', () {
      final big = _b64('a' * (KitTerminalOsc52.maxBytes + 1));
      expect(KitTerminalOsc52.parse(['c', big]), isNull);
      expect(
        KitTerminalOsc52.parse(['c', _b64('a' * KitTerminalOsc52.maxBytes)]),
        isNotNull,
      );
    });

    test('garbage and empty payloads are ignored', () {
      expect(KitTerminalOsc52.parse(['c', '!!!not base64!!!']), isNull);
      expect(KitTerminalOsc52.parse(['c', '']), isNull);
      expect(KitTerminalOsc52.parse(['c']), isNull);
    });
  });

  group('wrapped link detection', () {
    xterm.Terminal terminalWith(String text, {int width = 40}) {
      final t = xterm.Terminal(maxLines: 100);
      t.resize(width, 20);
      t.write(text);
      return t;
    }

    test('a soft-wrapped link is one link from any of its rows', () {
      final t = terminalWith('Use the url below:\r\n$_url\r\n');
      for (final y in [1, 2, 3]) {
        expect(KitTerminalLinks.urlAt(t, xterm.CellOffset(3, y)), _url);
      }
      expect(KitTerminalLinks.urlAt(t, xterm.CellOffset(3, 0)), isNull);
    });

    test('a link the program wrapped itself with newlines is joined', () {
      final rows = [
        for (var i = 0; i < _url.length; i += 40)
          _url.substring(i, i + 40 > _url.length ? _url.length : i + 40),
      ];
      final t = terminalWith('${rows.join('\r\n')}\r\n');
      expect(KitTerminalLinks.urlAt(t, xterm.CellOffset(1, 2)), _url);
    });

    test('trailing punctuation is not part of the link', () {
      final t = terminalWith('see https://a.example/x). ok\r\n');
      expect(
        KitTerminalLinks.urlAt(t, xterm.CellOffset(8, 0)),
        'https://a.example/x',
      );
      expect(KitTerminalLinks.urlAt(t, xterm.CellOffset(0, 0)), isNull);
    });
  });

  group('in the live view', () {
    Future<xterm.Terminal> pump(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(412, 915)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final terminal = xterm.Terminal(maxLines: 200);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: KitTerminalView.live(
              terminal: terminal,
              semanticsLabel: 'Terminal',
              autofocus: false,
            ),
          ),
        ),
      );
      await tester.pump();
      addTearDown(() async {});
      return terminal;
    }

    testWidgets('OSC 52 puts text on the clipboard and says so', (
      tester,
    ) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final terminal = await pump(tester);
      terminal.write('\x1b]52;c;?\x07');
      terminal.write('\x1b]52;c;${_b64('first')}\x07');
      await tester.pump();
      expect(copied, ['first']);
      expect(find.text('Copied to clipboard'), findsWidgets);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('tapping a wrapped link offers Open and Copy', (tester) async {
      final terminal = await pump(tester);
      terminal.write('$_url\r\n');
      await tester.pump();
      final origin = tester.getTopLeft(find.byType(xterm.TerminalView));
      await tester.tapAt(origin + const Offset(40, 14));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('terminal-link-sheet')), findsOneWidget);
      expect(find.text(_url), findsOneWidget);
      expect(find.text('Open link'), findsOneWidget);
      expect(find.text('Copy link'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('tapping plain text opens nothing', (tester) async {
      final terminal = await pump(tester);
      terminal.write('hello world\r\n');
      await tester.pump();
      final origin = tester.getTopLeft(find.byType(xterm.TerminalView));
      await tester.tapAt(origin + const Offset(40, 14));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('terminal-link-sheet')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
