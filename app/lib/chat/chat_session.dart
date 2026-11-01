import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:opencode_runtime/opencode_runtime.dart';

/// The app's view of the one resident OpenCode server: observes its state, starts it on demand, brings it back
/// after an idle or memory stop, and tells the chat WebView when the server it should talk to changed.
class ChatSession extends ChangeNotifier {
  ChatSession(this._runtime, {required this._isForeground}) {
    _sub = _runtime.serverState.listen(_onSnapshot);
  }

  final RuntimeApi _runtime;
  final bool Function() _isForeground;
  late final StreamSubscription<ServerSnapshot> _sub;

  ServerSnapshot _snapshot = const ServerSnapshot(status: ServerStatus.stopped);
  int _generation = 0;
  Future<void>? _starting;
  bool _disposed = false;

  ServerSnapshot get snapshot => _snapshot;

  /// Increments whenever the (port, password) of the running server changes: the WebView must reload.
  int get generation => _generation;

  Uri? get base => _snapshot.isRunning ? Uri.parse('http://127.0.0.1:${_snapshot.port}/') : null;
  String? get password => _snapshot.isRunning ? _snapshot.password : null;

  void _onSnapshot(ServerSnapshot next) {
    final prev = _snapshot;
    _snapshot = next;
    if (next.isRunning && (!prev.isRunning || prev.port != next.port || prev.password != next.password)) {
      _generation++;
    }
    _notify();
    // Stopped for idle/memory reasons while the user is looking at the app: bring it back.
    if (next.status == ServerStatus.stopped && next.stopReason != null && next.stopReason != 'user' && _isForeground()) {
      unawaited(ensureRunning());
    }
  }

  /// Starts the server unless it is already starting or running. Never throws: failures show up as a `failed`
  /// snapshot with the log tail.
  Future<void> ensureRunning() {
    final s = _snapshot.status;
    if (s == ServerStatus.running || s == ServerStatus.starting || s == ServerStatus.restarting) {
      return Future.value();
    }
    return _starting ??= _start().whenComplete(() => _starting = null);
  }

  Future<void> retry() => ensureRunning();

  /// Called when the app returns to the foreground.
  Future<void> onForeground() {
    final s = _snapshot;
    if (s.status == ServerStatus.stopped && s.stopReason != null && s.stopReason != 'user') return ensureRunning();
    return Future.value();
  }

  Future<void> _start() async {
    try {
      await _runtime.startServer();
    } catch (_) {
      // The failure arrives through the state stream with the log tail.
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub.cancel();
    super.dispose();
  }
}
