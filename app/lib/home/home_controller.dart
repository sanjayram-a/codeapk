import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/opencode_api.dart';

/// State of the Home tab: recent sessions (grouped by day) and the search box.
class HomeController extends ChangeNotifier {
  HomeController({
    required this._api,
    required this._extraDirectories,
    this.debounce = const Duration(milliseconds: 300),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final OpencodeApi? Function() _api;
  final Future<List<String>> Function() _extraDirectories;
  final DateTime Function() _now;
  final Duration debounce;

  List<SessionInfo> _sessions = const [];
  String _query = '';
  bool _loading = false;
  String? _error;
  Timer? _timer;
  int _generation = 0;
  bool _disposed = false;

  List<SessionGroup> get groups => groupSessions(_sessions, _now());
  bool get hasSessions => _sessions.isNotEmpty;
  String get query => _query;
  bool get loading => _loading;
  String? get error => _error;

  void setQuery(String q) {
    _query = q;
    _timer?.cancel();
    _timer = Timer(debounce, refresh);
    notifyListeners();
  }

  Future<void> refresh() async {
    _timer?.cancel();
    final api = _api();
    final mine = ++_generation;
    if (api == null) {
      _sessions = const [];
      _error = null;
      _finish(mine);
      return;
    }
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final dirs = await _directories(api);
      final result = await api.listSessions(directories: dirs, search: _query.trim());
      if (mine != _generation) return; // a newer refresh is in flight or done
      _sessions = result;
    } on OpencodeApiException catch (e) {
      if (mine != _generation) return;
      _error = e.message;
    } catch (e) {
      if (mine != _generation) return;
      _error = e.toString();
    }
    _finish(mine);
  }

  Future<void> delete(SessionInfo s) async {
    await _api()?.deleteSession(s.id, directory: s.directory);
    await refresh();
  }

  Future<void> rename(SessionInfo s, String title) async {
    await _api()?.renameSession(s.id, title, directory: s.directory);
    await refresh();
  }

  /// Folders a new session can start in: `/root`, OpenCode's projects and the folders under `/root/projects`.
  Future<List<String>> knownDirectories() async {
    final api = _api();
    return api == null ? ['/root'] : _directories(api);
  }

  Future<List<String>> _directories(OpencodeApi api) async {
    final dirs = <String>['/root'];
    try {
      dirs.addAll(await api.listProjects());
    } catch (_) {}
    try {
      dirs.addAll(await _extraDirectories());
    } catch (_) {}
    return dirs.toSet().toList();
  }

  void _finish(int mine) {
    if (mine != _generation) return;
    _loading = false;
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
