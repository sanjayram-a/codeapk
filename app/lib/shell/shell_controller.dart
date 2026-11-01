import 'package:flutter/foundation.dart';

import '../api/session.dart';

/// Cross-tab coordination: which tab is shown, a command waiting to run in the Terminal tab, and opening chat.
class ShellController extends ChangeNotifier {
  static const homeTab = 0;
  static const filesTab = 1;
  static const terminalTab = 2;
  static const settingsTab = 3;

  int _tab = homeTab;
  List<String>? _pendingCommand;

  /// Registered by the Terminal tab so a reset can close its sessions first.
  Future<void> Function()? closeAllTerminals;

  /// Registered by the shell: opens chat on a session, creating one in [directory] when [session] is null.
  Future<void> Function({SessionInfo? session, String? directory})? openChat;

  int get tab => _tab;

  void select(int tab) {
    if (tab == _tab) return;
    _tab = tab;
    notifyListeners();
  }

  /// Shows the Terminal tab and runs [argv] there so the user sees exactly what runs.
  void runInTerminal(List<String> argv) {
    _pendingCommand = argv;
    _tab = terminalTab;
    notifyListeners();
  }

  List<String>? takePendingCommand() {
    final c = _pendingCommand;
    _pendingCommand = null;
    return c;
  }
}
