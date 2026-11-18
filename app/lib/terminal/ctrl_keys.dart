import 'dart:convert';
import 'package:flutter/foundation.dart';

/// The byte a terminal expects for Ctrl+[ch]: letters and `@ [ \ ] ^ _` map to control codes 0..31
/// (`c` -> 0x03, `[` -> ESC). Anything else is sent as typed.
Uint8List ctrlChar(String ch) {
  if (ch.runes.length != 1) return Uint8List.fromList(utf8.encode(ch));
  final c = ch.runes.first;
  final upper = (c >= 0x61 && c <= 0x7a) ? c - 0x20 : c; // a-z -> A-Z
  if (upper >= 0x40 && upper <= 0x5f) return Uint8List.fromList([upper & 0x1f]);
  return Uint8List.fromList(utf8.encode(ch));
}

/// State of the sticky Ctrl button on the extra key row: when armed, the next single typed character is sent as
/// its control code and Ctrl disarms.
class CtrlState extends ChangeNotifier {
  bool _armed = false;

  bool get armed => _armed;

  void toggle() {
    _armed = !_armed;
    notifyListeners();
  }

  void disarm() {
    if (!_armed) return;
    _armed = false;
    notifyListeners();
  }

  /// Bytes to send for [data] typed on the soft keyboard, honouring a sticky Ctrl.
  Uint8List encode(String data) {
    if (_armed && data.runes.length == 1) {
      disarm();
      return ctrlChar(data);
    }
    return Uint8List.fromList(utf8.encode(data));
  }
}
