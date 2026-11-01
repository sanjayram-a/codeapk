import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:opencode_runtime/opencode_runtime.dart';

enum SetupPhase { idle, installing, selfTesting, ready, failed }

/// First-run flow: extract the Linux environment, then prove it works with a self-test.
class SetupController extends ChangeNotifier {
  SetupController(this._runtime);

  final RuntimeApi _runtime;

  SetupPhase _phase = SetupPhase.idle;
  int _entries = 0;
  Map<String, String> _selfTest = const {};
  String? _error;

  SetupPhase get phase => _phase;
  int get entries => _entries;
  Map<String, String> get selfTest => _selfTest;
  String? get error => _error;

  static const _requiredKeys = ['arch', 'node', 'python', 'opencode'];

  /// Safe to call again after a failure. Ignored while a run is in progress.
  Future<void> run() async {
    if (_phase == SetupPhase.installing || _phase == SetupPhase.selfTesting) return;
    _error = null;
    _entries = 0;
    _set(SetupPhase.installing);
    try {
      await for (final n in _runtime.install()) {
        _entries = n;
        notifyListeners();
      }
      _set(SetupPhase.selfTesting);
      final result = await _runtime.selfTest();
      final missing = _requiredKeys.where((k) => (result[k] ?? '').trim().isEmpty);
      if (missing.isNotEmpty) throw StateError('Self-test is missing: ${missing.join(', ')}');
      _selfTest = result;
      _set(SetupPhase.ready);
    } catch (e) {
      _error = _describe(e);
      _set(SetupPhase.failed);
    }
  }

  String _describe(Object e) =>
      e is PlatformException ? (e.message ?? e.code) : e.toString().replaceFirst(RegExp(r'^(Bad state|Exception): '), '');

  void _set(SetupPhase p) {
    _phase = p;
    notifyListeners();
  }
}
