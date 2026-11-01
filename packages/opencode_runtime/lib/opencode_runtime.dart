/// Dart API for the on-device OpenCode runtime (Alpine + proot inside the app sandbox).
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

enum ServerStatus { stopped, starting, running, restarting, failed }

/// The state of the one resident `opencode serve` process.
class ServerSnapshot {
  const ServerSnapshot({
    required this.status,
    this.port,
    this.password,
    this.error,
    this.logTail,
    this.stopReason,
  });

  final ServerStatus status;
  final int? port;
  final String? password;
  final String? error;
  final String? logTail;

  /// Why the server stopped: `user`, `idle` or `memory`. Only set while [status] is stopped.
  final String? stopReason;

  bool get isRunning => status == ServerStatus.running;

  factory ServerSnapshot.fromMap(Map<Object?, Object?> m) => ServerSnapshot(
        status: ServerStatus.values.firstWhere(
          (s) => s.name == m['state'],
          orElse: () => ServerStatus.stopped,
        ),
        port: m['port'] as int?,
        password: m['password'] as String?,
        error: m['error'] as String?,
        logTail: m['logTail'] as String?,
        stopReason: m['stopReason'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      other is ServerSnapshot &&
      other.status == status &&
      other.port == port &&
      other.password == password &&
      other.error == error &&
      other.stopReason == stopReason;

  @override
  int get hashCode => Object.hash(status, port, password, error, stopReason);
}

/// One entry of a folder listing in the sandbox home (guest path `/root`).
class FileEntry {
  const FileEntry({
    required this.name,
    required this.path,
    required this.isDir,
    required this.size,
    required this.modified,
  });

  final String name;
  final String path;
  final bool isDir;
  final int size;
  final DateTime modified;

  factory FileEntry.fromMap(Map<Object?, Object?> m) => FileEntry(
        name: m['name'] as String,
        path: m['path'] as String,
        isDir: m['isDir'] as bool,
        size: (m['size'] as num).toInt(),
        modified: DateTime.fromMillisecondsSinceEpoch((m['modifiedMs'] as num).toInt()),
      );
}

class EnvironmentInfo {
  const EnvironmentInfo({
    required this.rootfsBytes,
    required this.homeBytes,
    required this.rootfsVersion,
    required this.extraPackages,
  });

  final int rootfsBytes;
  final int homeBytes;
  final String? rootfsVersion;
  final List<String> extraPackages;

  factory EnvironmentInfo.fromMap(Map<Object?, Object?> m) => EnvironmentInfo(
        rootfsBytes: (m['rootfsBytes'] as num).toInt(),
        homeBytes: (m['homeBytes'] as num).toInt(),
        rootfsVersion: m['rootfsVersion'] as String?,
        extraPackages: List<String>.from(m['extraPackages'] as List? ?? const []),
      );
}

/// An interactive shell (or one command) running on a pseudo-terminal in the sandbox.
abstract class TerminalSession {
  /// Raw terminal output. Ends when the process exits.
  Stream<Uint8List> get output;
  Future<void> write(Uint8List bytes);
  Future<void> resize(int rows, int cols);
  Future<void> close();
}

/// Everything the app needs from the native runtime. The UI depends on this, so tests can use a fake.
abstract class RuntimeApi {
  /// Extracts the bundled rootfs if it is missing or outdated. Emits the number of entries extracted so far
  /// and completes when the rootfs is ready (immediately when it already is).
  Stream<int> install();

  /// Runs `uname -m`, `node -v`, `python3 -V` and `opencode --version` inside the sandbox.
  /// Keys: arch, node, python, opencode.
  Future<Map<String, String>> selfTest();

  /// Server state changes. The current state is delivered first, so a freshly started app attaches to a server
  /// that is already running.
  Stream<ServerSnapshot> get serverState;

  /// Starts the server (a no-op returning the current state when it is already running). Throws
  /// [PlatformException] with code `server_start` and the server's log tail in `details` when it cannot start.
  Future<ServerSnapshot> startServer({Map<String, String> env});

  Future<void> stopServer();

  /// The last lines of the server's output.
  Future<String> serverLog();

  /// Tells the runtime how many UI clients are attached (0 lets the idle timer run).
  Future<void> setClients(int n);
  Future<void> setIdleTimeoutMinutes(int minutes);

  /// Asks for the notification permission (Android 13+). Never throws; false when denied.
  Future<bool> requestNotificationPermission();

  /// Opens a shell, or runs [command] (argv) on a terminal in the sandbox.
  Future<TerminalSession> openTerminal({required int rows, required int cols, List<String>? command});

  // Files in the sandbox home. Paths are guest paths such as `/root/projects/a.py`.
  Future<List<FileEntry>> listFiles(String path);
  Future<void> createFolder(String path);
  Future<void> createFile(String path);
  Future<void> renameFile(String path, String newName);
  Future<void> deleteFile(String path);
  Future<void> copyFile(String src, String dstDir);
  Future<void> moveFile(String src, String dstDir);
  Future<String> readText(String path);
  Future<void> writeText(String path, String text);

  Future<EnvironmentInfo> environmentInfo();

  /// Deletes the Linux system (not `/root`). Fails with code `busy` while the server or a terminal is running.
  Future<void> resetEnvironment();
}

class OpencodeRuntime implements RuntimeApi {
  static const _methods = MethodChannel('opencode_runtime');
  static const _install = EventChannel('opencode_runtime/install');
  static const _state = EventChannel('opencode_runtime/state');

  Future<T?> _call<T>(String method, [Map<String, Object?>? args]) => _methods.invokeMethod<T>(method, args);

  @override
  Stream<int> install() => _install.receiveBroadcastStream().map((e) => e as int);

  @override
  Future<Map<String, String>> selfTest() async => Map<String, String>.from(await _call<Map>('selfTest') ?? const {});

  @override
  Stream<ServerSnapshot> get serverState =>
      _state.receiveBroadcastStream().map((e) => ServerSnapshot.fromMap(e as Map<Object?, Object?>));

  @override
  Future<ServerSnapshot> startServer({Map<String, String> env = const {}}) async =>
      ServerSnapshot.fromMap((await _call<Map>('startServer', {'env': env}))!);

  @override
  Future<void> stopServer() => _call<void>('stopServer');

  @override
  Future<String> serverLog() async => await _call<String>('serverLog') ?? '';

  @override
  Future<void> setClients(int n) => _call<void>('setClients', {'n': n});

  @override
  Future<void> setIdleTimeoutMinutes(int minutes) => _call<void>('setIdleTimeoutMinutes', {'minutes': minutes});

  @override
  Future<bool> requestNotificationPermission() async {
    try {
      return await _call<bool>('requestNotificationPermission') ?? false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<TerminalSession> openTerminal({required int rows, required int cols, List<String>? command}) async {
    final id = await _call<int>('terminalOpen', {'rows': rows, 'cols': cols, 'command': command});
    return _PlatformTerminal(id!);
  }

  @override
  Future<List<FileEntry>> listFiles(String path) async {
    final list = await _call<List>('fileList', {'path': path}) ?? const [];
    return [for (final e in list) FileEntry.fromMap(e as Map<Object?, Object?>)];
  }

  @override
  Future<void> createFolder(String path) => _call<void>('fileMkdir', {'path': path});

  @override
  Future<void> createFile(String path) => _call<void>('fileCreate', {'path': path});

  @override
  Future<void> renameFile(String path, String newName) => _call<void>('fileRename', {'path': path, 'newName': newName});

  @override
  Future<void> deleteFile(String path) => _call<void>('fileDelete', {'path': path});

  @override
  Future<void> copyFile(String src, String dstDir) => _call<void>('fileCopy', {'src': src, 'dstDir': dstDir});

  @override
  Future<void> moveFile(String src, String dstDir) => _call<void>('fileMove', {'src': src, 'dstDir': dstDir});

  @override
  Future<String> readText(String path) async => await _call<String>('fileReadText', {'path': path}) ?? '';

  @override
  Future<void> writeText(String path, String text) => _call<void>('fileWriteText', {'path': path, 'text': text});

  @override
  Future<EnvironmentInfo> environmentInfo() async =>
      EnvironmentInfo.fromMap((await _call<Map>('environmentInfo'))!);

  @override
  Future<void> resetEnvironment() => _call<void>('resetEnvironment');
}

class _PlatformTerminal implements TerminalSession {
  _PlatformTerminal(this.id) : _channel = EventChannel('opencode_runtime/terminal/$id');

  final int id;
  final EventChannel _channel;
  static const _methods = MethodChannel('opencode_runtime');

  @override
  Stream<Uint8List> get output => _channel.receiveBroadcastStream().map((e) => e as Uint8List);

  @override
  Future<void> write(Uint8List bytes) => _methods.invokeMethod<void>('terminalWrite', {'id': id, 'bytes': bytes});

  @override
  Future<void> resize(int rows, int cols) =>
      _methods.invokeMethod<void>('terminalResize', {'id': id, 'rows': rows, 'cols': cols});

  @override
  Future<void> close() => _methods.invokeMethod<void>('terminalClose', {'id': id});
}
