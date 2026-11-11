// Terminal SGR with colon sub-parameters (kitty / ECMA-48 style). Ink and
// chalk-based TUIs (Claude Code) send `4:0` to end an underline and
// `58:2::r:g:b` for its colour; a parser that reads the colons as digits
// turns `4:0` into SGR 40 and leaves everything underlined.
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/core.dart' as xterm;

bool _underlined(xterm.Terminal t, int x) =>
    t.buffer.lines[0].getAttributes(x) & xterm.CellAttr.underline != 0;

xterm.Terminal _write(String s) {
  final t = xterm.Terminal();
  t.resize(40, 5);
  t.write(s);
  return t;
}

void main() {
  test('plain 4 underlines and 24 ends it', () {
    final t = _write('\x1b[4mab\x1b[24mcd');
    expect(_underlined(t, 0), isTrue);
    expect(_underlined(t, 2), isFalse);
  });

  test('4:0 ends an underline and is not a black background', () {
    final t = _write('\x1b[4:1mab\x1b[4:0mcd');
    expect(_underlined(t, 1), isTrue);
    expect(_underlined(t, 2), isFalse);
    expect(t.buffer.lines[0].getBackground(2), 0);
  });

  test('4:3 is an underline, not a yellow background', () {
    final t = _write('\x1b[4:3mab\x1b[0mcd');
    expect(_underlined(t, 0), isTrue);
    expect(t.buffer.lines[0].getBackground(0), 0);
    expect(_underlined(t, 2), isFalse);
  });

  test('underline colour is consumed and does not leak into other styles', () {
    final t = _write('\x1b[4:3;58:2::255:0:0mab\x1b[59;24mcd\x1b[58;5;196mef');
    expect(_underlined(t, 0), isTrue);
    expect(_underlined(t, 2), isFalse);
    expect(
      t.buffer.lines[0].getForeground(4),
      t.buffer.lines[0].getForeground(2),
    );
    expect(_underlined(t, 4), isFalse);
  });

  test('colon true colour and 256 colour set the colour', () {
    final a = _write('\x1b[38:2::10:20:30mx\x1b[38:2:40:50:60my\x1b[48:5:99mz');
    final line = a.buffer.lines[0];
    expect(line.getForeground(0), line.getForeground(0));
    expect(line.getForeground(0) & 0xffffff, 0x0a141e);
    expect(line.getForeground(1) & 0xffffff, 0x28323c);
    expect(line.getBackground(2) & 0xff, 99);
    expect(_underlined(a, 0), isFalse);
  });

  test('a terminal reset (RIS) ends an underline left on', () {
    final t = _write('\x1b[4mab\x1bcxy');
    expect(_underlined(t, 0), isFalse);
    expect(t.buffer.lines[0].getText(0, 2), 'xy');
  });
}
