import 'package:flutter_test/flutter_test.dart';
import 'package:opencode_app/terminal/ctrl_keys.dart';

void main() {
  test('ctrlChar maps letters and brackets to control codes', () {
    expect(ctrlChar('c'), [3]);
    expect(ctrlChar('C'), [3]);
    expect(ctrlChar('d'), [4]);
    expect(ctrlChar('z'), [26]);
    expect(ctrlChar('['), [0x1b]);
    expect(ctrlChar('@'), [0]);
    expect(ctrlChar('_'), [31]);
  });

  test('ctrlChar leaves other characters and multi-character input alone', () {
    expect(ctrlChar('1'), [0x31]);
    expect(ctrlChar('é'), [0xc3, 0xa9]);
    expect(ctrlChar('ab'), [0x61, 0x62]);
    expect(ctrlChar(''), isEmpty);
  });

  test('sticky ctrl applies to one character, then disarms', () {
    final s = CtrlState();
    expect(s.encode('c'), [0x63]); // not armed
    s.toggle();
    expect(s.armed, isTrue);
    expect(s.encode('c'), [3]);
    expect(s.armed, isFalse);
    expect(s.encode('c'), [0x63]);
  });

  test('sticky ctrl stays armed through multi-character input such as escape sequences', () {
    final s = CtrlState()..toggle();
    expect(s.encode('\x1b[A'), [0x1b, 0x5b, 0x41]);
    expect(s.armed, isTrue);
  });
}
