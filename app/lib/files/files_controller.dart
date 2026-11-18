import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:opencode_runtime/opencode_runtime.dart';

/// State of the Files tab: the current folder of the sandbox home, a multi-selection and a copy/cut clipboard.
class FilesController extends ChangeNotifier {
  FilesController(this._runtime);

  static const root = '/root';

  final RuntimeApi _runtime;

  String _path = root;
  List<FileEntry> _entries = const [];
  bool _loading = false;
  String? _error;
  final Set<String> _selection = {};
  List<String> _clipboard = const [];
  bool _cut = false;
  bool _disposed = false;

  String get path => _path;
  List<FileEntry> get entries => _entries;
  bool get loading => _loading;
  String? get error => _error;
  Set<String> get selection => Set.unmodifiable(_selection);
  bool get hasClipboard => _clipboard.isNotEmpty;
  bool get canGoUp => _path != root;

  /// `(label, path)` for each folder from `/root` down to the current one.
  List<(String, String)> get crumbs {
    final out = <(String, String)>[('root', root)];
    var acc = root;
    for (final part in _path.substring(root.length).split('/').where((p) => p.isNotEmpty)) {
      acc = '$acc/$part';
      out.add((part, acc));
    }
    return out;
  }

  Future<void> open(String dir) => _load(dir);

  Future<void> up() async {
    if (!canGoUp) return;
    final i = _path.lastIndexOf('/');
    await _load(i <= root.length ? root : _path.substring(0, i));
  }

  Future<void> refresh() => _load(_path);

  void toggle(String path) {
    _selection.contains(path) ? _selection.remove(path) : _selection.add(path);
    notifyListeners();
  }

  void clearSelection() {
    _selection.clear();
    notifyListeners();
  }

  Future<void> createFolder(String name) => _named(name, (n) => _runtime.createFolder(_join(_path, n)));

  Future<void> createFile(String name) => _named(name, (n) => _runtime.createFile(_join(_path, n)));

  Future<void> rename(FileEntry e, String newName) => _named(newName, (n) => _runtime.renameFile(e.path, n));

  Future<void> deleteSelection() async {
    final paths = _selection.toList();
    _selection.clear();
    await _act(() async {
      for (final p in paths) {
        await _runtime.deleteFile(p);
      }
    });
  }

  /// True when every selected item is a file (folders cannot be downloaded).
  bool get selectionDownloadable =>
      _selection.isNotEmpty && _entries.where((e) => _selection.contains(e.path)).every((e) => !e.isDir);

  /// Saves the selected files to the phone's Downloads folder. Returns how many were saved; on failure the error is
  /// shown in the Files banner and the files saved so far are still counted.
  Future<int> downloadSelection() async {
    final paths = _selection.toList();
    _selection.clear();
    var saved = 0;
    try {
      for (final p in paths) {
        await _runtime.saveToDownloads(p);
        saved++;
      }
      _error = null;
    } catch (e) {
      _error = _describe(e);
    }
    notifyListeners();
    return saved;
  }

  void copySelection() => _setClipboard(cut: false);

  void cutSelection() => _setClipboard(cut: true);

  Future<void> paste() async {
    final items = _clipboard;
    final cut = _cut;
    if (items.isEmpty) return;
    await _act(() async {
      for (final p in items) {
        cut ? await _runtime.moveFile(p, _path) : await _runtime.copyFile(p, _path);
      }
    });
    if (_error == null && cut) {
      _clipboard = const [];
      notifyListeners();
    }
  }

  void _setClipboard({required bool cut}) {
    _clipboard = _selection.toList();
    _cut = cut;
    _selection.clear();
    notifyListeners();
  }

  Future<void> _named(String name, Future<void> Function(String) action) async {
    final n = name.trim();
    if (n.isEmpty || n == '.' || n == '..' || n.contains('/')) {
      _error = 'Names cannot be empty or contain "/".';
      notifyListeners();
      return;
    }
    await _act(() => action(n));
  }

  /// Runs a change, then reloads the current folder. Errors are shown and the listing is kept.
  Future<void> _act(Future<void> Function() change) async {
    try {
      await change();
      _error = null;
    } catch (e) {
      _error = _describe(e);
      notifyListeners();
      return;
    }
    await _load(_path);
  }

  Future<void> _load(String dir) async {
    _loading = true;
    notifyListeners();
    try {
      final list = await _runtime.listFiles(dir);
      _entries = [...list]..sort((a, b) {
          if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
      _path = dir;
      _selection.removeWhere((p) => !_entries.any((e) => e.path == p));
      _error = null;
    } catch (e) {
      _error = _describe(e);
    }
    _loading = false;
    notifyListeners();
  }

  String _join(String dir, String name) => dir == root ? '$root/$name' : '$dir/$name';

  String _describe(Object e) => e is PlatformException ? (e.message ?? e.code) : e.toString();

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
