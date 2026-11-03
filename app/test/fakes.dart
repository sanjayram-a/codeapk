import 'dart:async';
import 'dart:typed_data';

import 'package:opencode_app/api/opencode_api.dart';
import 'package:opencode_runtime/opencode_runtime.dart';

class FakeTerminal implements TerminalSession {
  FakeTerminal({this.command});

  final List<String>? command;
  final controller = StreamController<Uint8List>.broadcast();
  final written = <Uint8List>[];
  final resizes = <(int, int)>[];
  bool closed = false;

  @override
  Stream<Uint8List> get output => controller.stream;

  @override
  Future<void> write(Uint8List bytes) async => written.add(bytes);

  @override
  Future<void> resize(int rows, int cols) async => resizes.add((rows, cols));

  @override
  Future<void> close() async {
    closed = true;
    await controller.close();
  }
}

/// A scriptable [RuntimeApi]. Every call is appended to [log] so tests can assert on order.
class FakeRuntime implements RuntimeApi {
  final log = <String>[];

  // install / self-test
  List<int> installEvents = const [100, 200];
  Object? installError;
  int installCalls = 0;
  Map<String, String> selfTestResult = const {
    'arch': 'aarch64',
    'node': 'v24.0.0',
    'python': 'Python 3.14.0',
    'opencode': '1.19.4',
  };
  Object? selfTestError;

  // server
  ServerSnapshot current = const ServerSnapshot(status: ServerStatus.stopped);
  final _state = StreamController<ServerSnapshot>.broadcast();
  int startCalls = 0;
  Object? startError;
  ServerSnapshot startResult = const ServerSnapshot(status: ServerStatus.running, port: 4100, password: 'pw');
  String logText = 'server log';
  final clientCounts = <int>[];
  final idleMinutes = <int>[];

  void emit(ServerSnapshot s) {
    current = s;
    _state.add(s);
  }

  // notifications
  bool notificationsGranted = true;

  // terminals
  final terminals = <FakeTerminal>[];

  // files
  Map<String, List<FileEntry>> listings = {};
  Object? fileError;
  final texts = <String, String>{};

  // environment
  EnvironmentInfo env = const EnvironmentInfo(
    rootfsBytes: 400 * 1024 * 1024,
    homeBytes: 2 * 1024 * 1024,
    rootfsVersion: '2026.10.0',
    extraPackages: [],
  );

  @override
  Stream<int> install() async* {
    installCalls++;
    log.add('install');
    for (final e in installEvents) {
      yield e;
    }
    if (installError != null) throw installError!;
  }

  @override
  Future<Map<String, String>> selfTest() async {
    log.add('selfTest');
    if (selfTestError != null) throw selfTestError!;
    return selfTestResult;
  }

  @override
  Stream<ServerSnapshot> get serverState async* {
    yield current;
    yield* _state.stream;
  }

  @override
  Future<ServerSnapshot> startServer({Map<String, String> env = const {}}) async {
    startCalls++;
    log.add('startServer');
    if (startError != null) throw startError!;
    emit(startResult);
    return startResult;
  }

  @override
  Future<void> stopServer() async {
    log.add('stopServer');
    emit(const ServerSnapshot(status: ServerStatus.stopped, stopReason: 'user'));
  }

  @override
  Future<String> serverLog() async => logText;

  @override
  Future<void> setClients(int n) async => clientCounts.add(n);

  @override
  Future<void> setIdleTimeoutMinutes(int minutes) async => idleMinutes.add(minutes);

  @override
  Future<bool> requestNotificationPermission() async {
    log.add('notifications');
    return notificationsGranted;
  }

  @override
  Future<TerminalSession> openTerminal({required int rows, required int cols, List<String>? command}) async {
    log.add('openTerminal ${command?.join(' ') ?? 'shell'}');
    final t = FakeTerminal(command: command);
    terminals.add(t);
    return t;
  }

  @override
  Future<List<FileEntry>> listFiles(String path) async {
    log.add('list $path');
    if (fileError != null) throw fileError!;
    return listings[path] ?? const [];
  }

  @override
  Future<void> createFolder(String path) async => log.add('mkdir $path');

  @override
  Future<void> createFile(String path) async => log.add('create $path');

  @override
  Future<void> renameFile(String path, String newName) async => log.add('rename $path $newName');

  @override
  Future<void> deleteFile(String path) async {
    log.add('delete $path');
    if (fileError != null) throw fileError!;
  }

  @override
  Future<void> copyFile(String src, String dstDir) async => log.add('copy $src $dstDir');

  @override
  Future<void> moveFile(String src, String dstDir) async => log.add('move $src $dstDir');

  @override
  Future<String> readText(String path) async => texts[path] ?? '';

  @override
  Future<void> writeText(String path, String text) async {
    log.add('write $path');
    texts[path] = text;
  }

  @override
  Future<EnvironmentInfo> environmentInfo() async => env;

  StorageInfo storage = const StorageInfo(npmBytes: 0, pythonBytes: 0, projects: []);
  Completer<void>? storageGate;

  @override
  Future<StorageInfo> storageInfo() async {
    await storageGate?.future;
    return storage;
  }

  @override
  Future<int> clearCache(CacheKind kind) async {
    log.add('clearCache ${kind.name}');
    final freed = kind == CacheKind.npm ? storage.npmBytes : storage.pythonBytes;
    storage = StorageInfo(
      npmBytes: kind == CacheKind.npm ? 0 : storage.npmBytes,
      pythonBytes: kind == CacheKind.python ? 0 : storage.pythonBytes,
      projects: storage.projects,
    );
    return freed;
  }

  @override
  Future<String> saveToDownloads(String path) async {
    log.add('download $path');
    if (fileError != null) throw fileError!;
    return path.split('/').last;
  }

  @override
  Future<void> resetEnvironment() async => log.add('resetEnvironment');
}

FileEntry file(String name, {String dir = '/root', bool isDir = false, int size = 10}) => FileEntry(
      name: name,
      path: '$dir/$name',
      isDir: isDir,
      size: size,
      modified: DateTime(2026, 11, 1),
    );

class FakeOpencodeApi implements OpencodeApi {
  List<SessionInfo> sessions = [];
  Object? error;
  List<String> projects = [];
  final calls = <({List<String> dirs, String? search})>[];
  final deleted = <String>[];
  final renamed = <String>[];

  @override
  Future<List<SessionInfo>> listSessions({required List<String> directories, String? search, int limit = 50}) async {
    calls.add((dirs: directories, search: search));
    if (error != null) throw error!;
    return sessions;
  }

  @override
  Future<SessionInfo> createSession({required String directory, String? title}) async =>
      SessionInfo(id: 'new', title: title ?? '', directory: directory, updated: DateTime(2026, 11, 1));

  @override
  Future<void> renameSession(String id, String title, {String? directory}) async => renamed.add('$id=$title');

  @override
  Future<void> deleteSession(String id, {String? directory}) async => deleted.add(id);

  @override
  Future<List<String>> listProjects() async => projects;
}
