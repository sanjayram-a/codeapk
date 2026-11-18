# Service Lifecycle + App UI Implementation Plan (Phases 3–4)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the Phase 0–1 spike into the real app. The OpenCode server survives the app being swiped away, restarts after a crash and stops when idle. The UI is a native shell: onboarding, setup, a Home with recent sessions and search, a Files manager, a Terminal, and Settings (with Environment). The chat itself is the OpenCode web UI in a WebView, opened directly on a chosen session.

**Architecture:** All lifecycle policy is plain Kotlin behind small interfaces and is unit-tested on the JVM with a fake clock. These are `ServerController`, `TerminalManager`, `MemoryGuard` and `EnvironmentManager`. A process-wide `RuntimeHost` owns them. A foreground `RuntimeService` only exists to keep the process alive while the server runs; it holds no logic. The Flutter plugin talks to `RuntimeHost`, so a new Flutter engine can re-attach to a server that is already running. The Dart UI depends on an abstract `RuntimeApi` (process control, terminal, files) and an abstract `OpencodeApi` (OpenCode's HTTP API: sessions, projects), so every screen is tested with fakes. Files are managed natively by a Kotlin `FileManager` working directly on `files/home` (guest `/root`), so it works with the server off.

**Tech Stack:** Kotlin, JUnit4, Android `Service` (foregroundServiceType `specialUse`), Flutter 3.44 / Dart 3.12, `webview_flutter` (already in), `xterm` ^4.0.0, `shared_preferences` ^2.5.0.

**Spec:** `docs/superpowers/specs/2026-10-30-opencode-android-design.md` (sections 4, 6, 7 and Phases 3–4). Builds on `docs/superpowers/plans/2026-10-30-runtime-spike-and-native-layer.md`, which is complete. The two real-phone checks in `docs/spike-results.md` stay open and are not blocked by this plan.

**Out of scope (next plan):** Phase 2 (CI, Play asset pack, 16 KB proot rebuild), Phase 5 (LAN mode, SAF import/export, secure key storage), Phase 6 (device matrix, Play checklist).

## Global Constraints
- Existing names stay: app `dev.opencodeapk.app`, plugin `dev.opencodeapk.runtime`, channel `opencode_runtime`, install event channel `opencode_runtime/install`. Pinned versions live in `rootfs/versions.env`.
- `minSdk 26`, `targetSdk 36`, `compileSdk 36`. Permissions stay exactly `INTERNET`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_SPECIAL_USE`, `POST_NOTIFICATIONS`. No storage permissions.
- `RuntimeService` uses `foregroundServiceType="specialUse"` with a `PROPERTY_SPECIAL_USE_FGS_SUBTYPE` property saying honestly what it does.
- One resident `opencode serve` process. It binds `127.0.0.1` with a random per-start password. LAN mode is not part of this plan.
- Idle stop: default 15 min (configurable) with no client attached. Crash restart: at most 3 tries, then show the error and logs.
- Memory guard: stop idle terminal sessions first and the server last.
- Terminal: a PTY running `proot … /bin/bash -l` (`ProotLauncher` + `EnvBuilder`), multiple sessions, and an extra key row (Esc/Ctrl/Tab/arrows).
- Environment tab: runtime versions, disk usage, a visible-PTY `apk add build-base`, and "reset environment" that keeps `/root`.
- WebView rules from `app/lib/server_guard.dart` stay: localhost-only navigation, Basic auth answered only for our own server, external links go to the system browser.
- Navigation: bottom bar **Home · Files · Terminal · Settings**. Chat is a full-screen page pushed from Home (back returns to Home). Environment is a page under Settings.
- Chat = OpenCode web UI in the WebView (it already renders markdown, code, diffs, tool calls, permission prompts and provider login). Do not rebuild it natively in this plan.
- Home history/search/new-session use OpenCode's own HTTP API. Confirm the exact routes against the running server's OpenAPI (`GET /doc`) in Task 6 Step 1 and record them in `docs/opencode-api.md`.
- File manager is sandboxed to `files/home`: every path is resolved against that root and anything that escapes it is rejected. No `MANAGE_EXTERNAL_STORAGE`.
- Onboarding shows a disclosure ("a Linux environment runs in this app's private sandbox, and the AI can run commands there") and needs consent before anything is installed or started.
- JVM tests: `cd app/android && ./gradlew :opencode_runtime:testDebugUnitTest`. Dart tests: `cd app && flutter test`.

## Review Focus
1. **App swiped from recents while the server runs.** The server keeps running. When the app reopens, the UI shows the existing server and does not start a second one. → Task 4 `RuntimeHost` is process-wide, and Task 6 `chat_session_test` `attachesToRunningServer`.
2. **A crash loop.** The server dies on every start. After 3 restarts the state is `failed` with the log tail, with no endless loop and no restart storm. → Task 1 `givesUpAfterMaxRestarts`.
3. **Idle stop must not kill real work.** If a terminal is open, or OpenCode is mid-task with the app in the background, the idle timer must not fire. If the busy check itself fails, treat the server as busy. → Task 1 `idleNeverStopsWithTerminalOrBusyServer`, `busyProbeErrorCountsAsBusy`.
4. **Restart changes port and password.** The WebView must reload on the new origin, not keep talking to the dead one. → Task 6 `chat_session_test` `reloadsWhenPortOrPasswordChanges`.
5. **Terminal edge cases.** Resize to 0×0 or a huge size, writing to a session that already exited, and output arriving after close. → Task 2 `clampsResize`, `writeAfterExitIsIgnored`.
6. **Reset environment while things are running**, or with the app killed halfway. It must refuse while the server or a terminal is active, and must never touch `/root`. → Task 3 `refusesWhileBusy`, `keepsHome`.
7. **File manager escapes the sandbox** (`..`, symlinks to outside, absolute paths) or deletes `/root`. → Task 3b `rejectsTraversal`, `rejectsSymlinkEscape`, `deleteRefusesRoot`.
8. **Search typing storm and odd titles** (empty titles, server offline while Home is open). → Task 6 `home_controller_test`.
9. **Notification permission denied** (Android 13+). The server must still run and onboarding must not block. → Task 5 `deniedNotificationsDoNotBlock`.

---

## File Structure
```
packages/opencode_runtime/android/src/main/kotlin/dev/opencodeapk/runtime/
  ServerController.kt     state machine: start/stop, crash restart, idle stop, state snapshots (pure, fake-clock tested)
  TerminalManager.kt      PTY sessions by id, attached tracking, clamped resize
  MemoryGuard.kt          onTrimMemory policy
  EnvironmentManager.kt   info() and reset() for the Environment page
  FileManager.kt          sandboxed file operations on /root
  RuntimeHost.kt          process-wide singleton wiring the above + a 1 s ticker
  RuntimeService.kt       foreground service + notification (Stop action)
  OpencodeRuntimePlugin.kt  (modify) channels delegate to RuntimeHost
  ServerSupervisor.kt     (modify) implements ServerBackend
packages/opencode_runtime/android/src/test/kotlin/dev/opencodeapk/runtime/
  ServerControllerTest.kt, TerminalManagerTest.kt, MemoryGuardTest.kt, EnvironmentManagerTest.kt, FileManagerTest.kt
packages/opencode_runtime/lib/opencode_runtime.dart   RuntimeApi, OpencodeRuntime, ServerSnapshot, TerminalSession
app/lib/
  main.dart                       runApp(OpencodeApp(runtime: OpencodeRuntime(), prefs: …))
  app.dart                        gate: consent → setup → home
  settings/settings_store.dart    consent + idle minutes (shared_preferences)
  onboarding/onboarding_screen.dart
  setup/setup_controller.dart, setup/setup_screen.dart
  shell/home_shell.dart           NavigationBar + IndexedStack (keeps the WebView alive)
  api/opencode_api.dart, api/session.dart   OpenCode HTTP client (sessions, projects)
  home/home_controller.dart, home/home_tab.dart   recent sessions + search + new session
  chat/chat_session.dart, chat/chat_page.dart     server lifecycle for the app + WebView on a session; server_guard.dart (kept)
  files/files_controller.dart, files/files_tab.dart, files/file_editor_page.dart
  terminal/key_bytes.dart, terminal/extra_keys.dart, terminal/terminal_tab.dart
  environment/environment_page.dart
  settings/settings_tab.dart
app/test/   key_bytes_test, settings_store_test, setup_controller_test, opencode_api_test, home_controller_test, chat_session_test, files_controller_test, tabs_test, app_gate_test
app/android/app/src/main/AndroidManifest.xml   (modify) service declaration
```

---

### Task 1: ServerController (restart, idle stop, state)

**Files:** Create `ServerController.kt`. Modify `ServerSupervisor.kt` to implement `ServerBackend`. Test: `ServerControllerTest.kt`.

**Interfaces:**
- Consumes: `ServerSupervisor.start(extraEnv): ServerInfo`, `stop()`, `isRunning()`, `log.tail()`, `Clock` (from `Processes.kt`).
- Produces:
  ```kotlin
  interface ServerBackend { fun start(extraEnv: Map<String,String>): ServerInfo; fun stop(); fun isRunning(): Boolean; fun logTail(): String }
  enum class ServerState { STOPPED, STARTING, RUNNING, RESTARTING, FAILED }
  data class ServerSnapshot(val state: ServerState, val port: Int? = null, val password: String? = null,
                            val error: String? = null, val logTail: String? = null, val stopReason: String? = null)
  data class ControllerConfig(val idleTimeoutMs: Long = 15 * 60_000, val maxRestarts: Int = 3,
                              val restartBackoffMs: List<Long> = listOf(1_000, 3_000, 10_000),
                              val stableResetMs: Long = 10 * 60_000)
  class ServerController(backend: ServerBackend, clock: Clock, sessions: () -> Int, busy: () -> Boolean,
                         config: ControllerConfig = ControllerConfig(), onState: (ServerSnapshot) -> Unit) {
      val snapshot: ServerSnapshot
      fun start(extraEnv: Map<String,String> = emptyMap()): ServerSnapshot   // blocking; no-op returning the current snapshot if already RUNNING
      fun stop(reason: String = "user")                                       // never restarts afterwards
      fun setClients(n: Int)                                                  // UI clients attached
      fun setIdleTimeout(ms: Long)
      fun tick()                                                              // called about once per second
  }
  ```
  `sessions()` is the number of open terminal sessions. `busy()` is true while OpenCode is working. Every state change calls `onState`.

- [ ] **Step 1: Write failing tests** with a `FakeBackend` (scriptable `start` results, `alive` flag) and a manual `FakeClock`:
  - `startMovesThroughStartingToRunning`: `onState` sees `STARTING`, then `RUNNING` with the backend's port and password.
  - `startWhenRunningIsNoOp`: the second `start` returns the same port, and `backend.starts == 1`. This covers an app that is reopened after a swipe-away.
  - `restartsAfterCrashWithBackoff`: after `RUNNING`, set `alive=false`. `tick()` gives `RESTARTING`. A `tick()` before 1 s has passed does nothing. After 1 s it calls `backend.start`, and the state is `RUNNING` with the new port and password.
  - `givesUpAfterMaxRestarts`: `backend.start` throws `ServerStartException("x", "boom")` every time. After 3 backoff rounds the state is `FAILED`, `logTail` contains `boom`, and 10 more `tick()` calls cause no more `start` calls.
  - `restartCounterResetsAfterStableRun`: run 10 min, crash, crash again. The restart count restarted from 0, so `FAILED` is not reached early.
  - `userStopNeverRestarts`: `stop()` gives `STOPPED` with `stopReason == "user"`, and later `tick()` calls do not start the backend.
  - `idleStopsAfterTimeout`: `RUNNING`, `setClients(0)`, `sessions()==0`, `busy()==false`. After 15 min, `tick()` gives `STOPPED` with `stopReason == "idle"`.
  - `attachedClientResetsIdle`: `setClients(1)` and 20 min pass, no stop. Then `setClients(0)`, and the timeout counts from that moment.
  - `idleNeverStopsWithTerminalOrBusyServer`: `sessions()==1` for 30 min means no stop. `busy()==true` for 30 min means no stop.
  - `busyProbeErrorCountsAsBusy`: `busy` throws, `tick()` does not stop and does not crash.
- [ ] **Step 2:** Run `./gradlew :opencode_runtime:testDebugUnitTest --tests '*ServerControllerTest*'`. Expected: FAIL (class missing).
- [ ] **Step 3: Implement `ServerController`.** It is a synchronized state machine with no threads of its own; the caller drives it with `tick()`. `tick()` runs the restart and idle logic. Wrap the `busy()` call in try/catch and treat any exception as busy. Make `ServerSupervisor` implement `ServerBackend` (`logTail() = log.tail(50)`).
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5: Commit** `feat(runtime): server controller with crash restart and idle stop`.

### Task 2: TerminalManager + MemoryGuard

**Files:** Create `TerminalManager.kt`, `MemoryGuard.kt`. Tests: `TerminalManagerTest.kt`, `MemoryGuardTest.kt`.

**Interfaces:**
- Consumes: `PtySession` (real PTY), `ProotLauncher.argv`, `EnvBuilder.build`, `ServerController` (Task 1).
- Produces:
  ```kotlin
  interface TerminalProcess { val output: InputStream; fun write(b: ByteArray); fun resize(rows: Int, cols: Int); fun waitFor(): Int; fun close() }
  fun interface TerminalFactory { fun open(command: List<String>?, rows: Int, cols: Int): TerminalProcess } // null = login shell
  class TerminalManager(factory: TerminalFactory, onOutput: (id: Int, bytes: ByteArray) -> Unit, onExit: (id: Int, code: Int) -> Unit) {
      fun open(command: List<String>?, rows: Int, cols: Int): Int      // returns the session id
      fun write(id: Int, bytes: ByteArray); fun resize(id: Int, rows: Int, cols: Int); fun close(id: Int)
      fun setAttached(id: Int, attached: Boolean)                      // Dart listening or not
      fun count(): Int; fun detachedIds(): List<Int>; fun closeAll()
  }
  object MemoryGuard { fun onTrim(level: Int, terminals: TerminalManager, controller: ServerController, clients: Int) }
  ```
  The real `TerminalFactory` wraps `PtySession` and runs `ProotLauncher.argv(paths, command ?: listOf("/bin/bash","-l"))` with `EnvBuilder.build(paths)`.

- [ ] **Step 1: Write failing tests** (a `FakeTerminalProcess` that records calls and lets the test push output or exit):
  - `opensAndRoutesOutputById`: two sessions get different ids, and output from each reaches `onOutput` with the right id.
  - `clampsResize`: `resize(id, 0, 0)` reaches the process as `(1, 1)`. `resize(id, 99999, 99999)` reaches it as `(500, 500)`.
  - `writeAfterExitIsIgnored`: after the process exits, `onExit(id, code)` fired once, and `write` or `resize` on that id does not throw.
  - `closeRemovesSessionAndStopsOutput`: after `close(id)`, `count()` drops by one and later fake output is not delivered.
  - `detachedIdsTracksAttachedFlag`: a new session counts as detached until `setAttached(id, true)`.
  - MemoryGuard: `level < 10` (`TRIM_MEMORY_RUNNING_LOW`) does nothing. Level 10 to 14 closes only detached terminals. Level ≥ 15 (`TRIM_MEMORY_RUNNING_CRITICAL`) also calls `controller.stop("memory")` only when `clients == 0`. With `clients > 0` the server is kept. Use a fake `ServerBackend` with a real `ServerController`.
- [ ] **Step 2:** Run both test classes. Expected: FAIL.
- [ ] **Step 3: Implement.** One reader thread per session pumps `output` into `onOutput` and then calls `onExit(id, waitFor())`. Clamp is `coerceIn(1, 500)`. All map access is synchronized.
- [ ] **Step 4:** Run. Expected: PASS.
- [ ] **Step 5: Commit** `feat(runtime): terminal sessions and memory guard`.

### Task 3: EnvironmentManager (info, reset)

**Files:** Create `EnvironmentManager.kt`. Test: `EnvironmentManagerTest.kt`.

**Interfaces:**
- Consumes: `Paths`, `RootfsInstaller.installedVersion()`, `FileOps.deleteRecursively`.
- Produces:
  ```kotlin
  data class EnvironmentInfo(val rootfsBytes: Long, val homeBytes: Long, val rootfsVersion: String?, val extraPackages: List<String>)
  class EnvironmentManager(paths: Paths, ops: FileOps, isBusy: () -> Boolean) {
      fun info(): EnvironmentInfo          // extraPackages = non-blank lines of home/.apk-extra
      fun reset()                          // throws IllegalStateException("busy") if isBusy()
  }
  ```
  `reset` deletes `rootfs`, `rootfs.new` and `rootfs.old`, and `tmp` and `proot-tmp`. It never touches `home`.

- [ ] **Step 1: Write failing tests** (temp dir plus `RecordingFileOps` from `RootfsInstallerTest.kt`):
  - `infoSumsSizesAndReadsExtras`: known file sizes in `rootfs/` and `home/`, and `home/.apk-extra` = `"build-base\n\nvim\n"`, give the exact byte totals and `listOf("build-base","vim")`.
  - `keepsHome`: after `reset()`, `home/projects/a.py` still exists with the same content, and `rootfs`, `rootfs.new` and `rootfs.old` are gone.
  - `refusesWhileBusy`: `isBusy=true` means `reset()` throws and nothing is deleted.
  - `infoOnMissingRootfs`: no `rootfs` folder gives `rootfsBytes == 0` and `rootfsVersion == null`.
- [ ] **Step 2:** Run. Expected: FAIL. **Step 3:** Implement (walk the tree for sizes; skip symlinks). **Step 4:** Run. Expected: PASS.
- [ ] **Step 5: Commit** `feat(runtime): environment info and reset`.

### Task 3b: FileManager (native, sandboxed to /root)

**Files:** Create `FileManager.kt`. Test: `FileManagerTest.kt`. Wired to the plugin in Task 4.

**Interfaces:**
- Consumes: `Paths.home`.
- Produces:
  ```kotlin
  data class FileEntry(val name: String, val path: String, val isDir: Boolean, val size: Long, val modifiedMs: Long)
  class FileManager(private val home: File) {   // paths are guest paths: "/root", "/root/projects/a.py"
      fun list(path: String): List<FileEntry>          // folders first, then files, each case-insensitive alphabetical
      fun mkdir(path: String); fun createFile(path: String)
      fun rename(path: String, newName: String)        // newName must not contain '/'
      fun delete(path: String)                         // recursive; refuses "/root" itself
      fun copy(src: String, dstDir: String); fun move(src: String, dstDir: String)
      fun readText(path: String, maxBytes: Long = 1_048_576): String   // throws if larger, or if binary (NUL byte in first 8 KB)
      fun writeText(path: String, text: String)        // atomic: temp file + rename
  }
  ```
  Every method resolves its guest path against `home` and throws `SecurityException` if the canonical result is outside `home` (covers `..`, absolute paths outside `/root`, and symlinks that point outside).

- [ ] **Step 1: Write failing tests** (temp dir as `home`): `listsFoldersFirstThenFiles`; `rejectsTraversal` (`/root/../x`, `/etc/passwd`, `/root/../../x`); `rejectsSymlinkEscape` (a symlink inside home to a file outside: `readText`, `writeText`, `delete` throw `SecurityException`; skip where the OS cannot create symlinks); `deleteRefusesRoot`; `renameRejectsSlashAndExistingName`; `copyAndMoveIntoSubfolder` (copying a folder into itself throws); `readTextRejectsBinaryAndOversize`; `writeTextReplacesContent`; `emptyPathMeansRoot`.
- [ ] **Step 2:** Run `--tests '*FileManagerTest*'`. Expected: FAIL. **Step 3:** Implement. **Step 4:** Run. Expected: PASS.
- [ ] **Step 5: Commit** `feat(runtime): sandboxed file manager`.

### Task 4: RuntimeHost + RuntimeService + plugin channels

**Files:** Create `RuntimeHost.kt`, `RuntimeService.kt`. Modify `OpencodeRuntimePlugin.kt`, `packages/opencode_runtime/android/src/main/AndroidManifest.xml` (service declaration with the special-use property), `packages/opencode_runtime/lib/opencode_runtime.dart`. There are no JVM tests for the Android glue; it is verified on a device in Task 9.

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces `object RuntimeHost`:
  - `fun get(context: Context): RuntimeHost` lazily builds Paths, `ServerSupervisor`, `ServerController` (with `sessions = terminals::count`, and `busy` = the Step 1 probe), `TerminalManager`, `EnvironmentManager`, `FileManager` and a single-thread 1 s `ScheduledExecutorService` that calls `controller.tick()`. It is created once per process.
  - `fun addListener(l: HostListener)` / `removeListener`, where `HostListener` gets `onServerState(ServerSnapshot)`, `onTerminalOutput(id, bytes)` and `onTerminalExit(id, code)`. The listener list is `CopyOnWriteArrayList`, so a new Flutter engine can re-attach.
  - `RuntimeService`: `startForeground` with a low-importance channel `runtime`, title "OpenCode is running", text "Private Linux sandbox on this device" and a "Stop" action. The service starts when the state becomes `RUNNING` and stops when it becomes `STOPPED` or `FAILED`.
- MethodChannel `opencode_runtime` adds: `serverSnapshot`, `setClients{n}`, `setIdleTimeoutMinutes{minutes}`, `terminalOpen{rows,cols,command?} -> id`, `fileList{path}`, `fileMkdir`, `fileCreate`, `fileRename{path,newName}`, `fileDelete`, `fileCopy{src,dstDir}`, `fileMove{src,dstDir}`, `fileReadText{path}`, `fileWriteText{path,text}` (all delegate to `FileManager`; a `SecurityException` becomes a PlatformException with code `outside_sandbox`), `terminalWrite{id,bytes}`, `terminalResize{id,rows,cols}`, `terminalClose{id}`, `environmentInfo`, `resetEnvironment`. `startServer` and `stopServer` now call the controller. New EventChannels:
  - `opencode_runtime/state`: emits a map `{state, port, password, error, logTail, stopReason}` on every change, and the current one first on listen.
  - `opencode_runtime/terminal`: one stream per terminal id, with the id passed as the listen `arguments`. It emits `Uint8List` chunks, then ends on exit. Its `onListen`/`onCancel` call `setAttached`.
- Dart (`opencode_runtime.dart`):
  ```dart
  enum ServerStatus { stopped, starting, running, restarting, failed }
  class ServerSnapshot { final ServerStatus status; final int? port; final String? password; final String? error; final String? logTail; final String? stopReason; }
  class EnvironmentInfo { final int rootfsBytes, homeBytes; final String? rootfsVersion; final List<String> extraPackages; }
  abstract class TerminalSession { Stream<Uint8List> get output; Future<void> write(Uint8List b); Future<void> resize(int rows, int cols); Future<void> close(); }
  abstract class RuntimeApi {
    Stream<int> install();
    Future<Map<String,String>> selfTest();
    Stream<ServerSnapshot> get serverState;                 // current value first
    Future<ServerSnapshot> startServer({Map<String,String> env});   // returns when running, or throws PlatformException(code: 'server_start', details: logTail)
    Future<void> stopServer();
    Future<String> serverLog();
    Future<void> setClients(int n);
    Future<void> setIdleTimeoutMinutes(int minutes);
    Future<TerminalSession> openTerminal({required int rows, required int cols, List<String>? command});
    Future<EnvironmentInfo> environmentInfo();
    Future<void> resetEnvironment();
  }
  // plus: Future<List<FileEntry>> listFiles(String path); mkdir, createFile, rename, deleteFile, copyFile, moveFile; Future<String> readText(path); writeText(path, text)
  class OpencodeRuntime implements RuntimeApi { … }
  ```
  `startServer` no longer returns `({int port, String password})`; callers move to `ServerSnapshot`.

- [ ] **Step 1: Busy probe.** Start the app's server on the emulator, then fetch `/doc` (OpenAPI) with Basic auth and find the session-status endpoint. Expected: `GET /session/status`. Record the endpoint and the "busy" shape in a comment at the top of `RuntimeHost.kt`. Implement `isServerBusy(port, password): Boolean`, which returns true when any session is busy and **throws on any HTTP or parse error**, so Task 1's rule treats it as busy.
- [ ] **Step 2:** Implement `RuntimeHost` and `RuntimeService`. Declare the service in the plugin manifest (`android:exported="false"`, `foregroundServiceType="specialUse"`) with `<property android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE" android:value="Runs the user-configured OpenCode coding-agent server in a private Linux sandbox"/>`. `onTrimMemory` is forwarded from the service and the plugin's `ComponentCallbacks2` to `MemoryGuard.onTrim`.
- [ ] **Step 3:** Rewrite `OpencodeRuntimePlugin` so every call and stream goes through `RuntimeHost.get(context)`. On engine detach it only removes its listener and **does not stop the server**.
- [ ] **Step 4:** Add the Dart API above. Keep `install()` and `selfTest()` as they are.
- [ ] **Step 5: Verify:** `cd app && flutter analyze` is clean. `cd app/android && ./gradlew :opencode_runtime:testDebugUnitTest` is all green. `cd app && flutter build apk --debug` succeeds. (`app/lib/main.dart` still uses the old spike code; adapt its `startServer` call to `ServerSnapshot` just so it compiles. Task 5 replaces it.)
- [ ] **Step 6: Commit** `feat(runtime): runtime host, foreground service and channels`.

### Task 5: App gate — settings, onboarding, setup

**Files:** Create `app/lib/app.dart`, `settings/settings_store.dart`, `onboarding/onboarding_screen.dart`, `setup/setup_controller.dart`, `setup/setup_screen.dart`. Replace `app/lib/main.dart`. Modify `app/pubspec.yaml` (add `shared_preferences`, `xterm`). Tests: `settings_store_test.dart`, `setup_controller_test.dart`, `app_gate_test.dart` (with a `FakeRuntime implements RuntimeApi` in `app/test/fakes.dart`).

**Interfaces:**
- Produces:
  ```dart
  class SettingsStore { SettingsStore(SharedPreferences p);
    bool get consentAccepted; Future<void> acceptConsent();
    int get idleMinutes;                       // default 15, clamped 1..240
    Future<void> setIdleMinutes(int m); }
  class SetupController extends ChangeNotifier {
    SetupController(RuntimeApi runtime);
    SetupPhase get phase;   // idle, installing, selfTesting, ready, failed
    int get entries; Map<String,String> get selfTest; String? get error;
    Future<void> run();     // install → selfTest; safe to call again after failure
  }
  class OpencodeApp extends StatelessWidget { OpencodeApp({required RuntimeApi runtime, required SettingsStore settings}); }
  ```
  The gate shows `OnboardingScreen` until consent, then `SetupScreen` until `ready`, then `HomeShell` (Task 6).
- Onboarding copy (fixed): title "A Linux environment on your phone". Body: "OpenCode runs inside a private Linux environment in this app's own storage. The AI can run commands there — install packages, edit files and use the network — but it cannot see your other apps or files. Your prompts go to the AI provider you configure." Button "I understand, continue". A second button, "Allow notifications" (so you can see that OpenCode is running), asks for the permission with `Permission`-free plugin API: `runtime.requestNotificationPermission()` (add it to `RuntimeApi`, Android 13+, always resolves, never throws). It does not block "continue".

- [ ] **Step 1: Write failing tests:**
  - `settings_store_test`: default `idleMinutes == 15`. `setIdleMinutes(0)` stores 1 and `setIdleMinutes(9999)` stores 240. `consentAccepted` is false until `acceptConsent()`, and persists across a new store on the same prefs.
  - `setup_controller_test`: success path gives phases `installing → selfTesting → ready`, with `entries` updated from the stream. An install stream that errors gives `failed` with `error` set. A second `run()` retries and reaches `ready`. A self-test that returns fewer than 4 keys gives `failed`.
  - `app_gate_test` (widget): fresh prefs show the disclosure text. Tapping "I understand, continue" shows the setup screen. The runtime's `install()` is **not** called before consent. `deniedNotificationsDoNotBlock`: the fake `requestNotificationPermission` returns false, and "I understand, continue" still works.
- [ ] **Step 2:** Run `cd app && flutter test`. Expected: FAIL.
- [ ] **Step 3:** Implement. `main.dart` is `WidgetsFlutterBinding.ensureInitialized()`, load prefs, `runApp`. Add the Android-side `requestNotificationPermission` method to the plugin (uses `ActivityAware` to get the activity, and returns immediately when SDK < 33).
- [ ] **Step 4:** Run `flutter test`. Expected: PASS. **Step 5: Commit** `feat(app): onboarding, consent and setup flow`.

### Task 6: OpencodeApi + Home (recent sessions, search) + Chat page

**Files:** Create `app/lib/api/opencode_api.dart`, `app/lib/api/session.dart`, `app/lib/home/home_controller.dart`, `app/lib/home/home_tab.dart`, `app/lib/chat/chat_page.dart`, `app/lib/chat/chat_session.dart`, `app/lib/shell/home_shell.dart`, `docs/opencode-api.md`. Keep `server_guard.dart` and its test. Tests: `opencode_api_test.dart`, `home_controller_test.dart`, `chat_session_test.dart`.

**Interfaces:**
- Consumes: `RuntimeApi.serverState/startServer/setClients`, `isOwnServer`, `shouldAnswerAuth`.
- Produces:
  ```dart
  class SessionInfo { final String id; final String title; final String? directory; final DateTime updated; }
  abstract class OpencodeApi {
    Future<List<SessionInfo>> listSessions({String? search, int limit = 50});   // newest first
    Future<SessionInfo> createSession({required String directory, String? title});
    Future<void> renameSession(String id, String title);
    Future<void> deleteSession(String id);
    Future<List<String>> listProjects();                                          // known project directories
  }
  class HttpOpencodeApi implements OpencodeApi { HttpOpencodeApi({required Uri base, required String password, HttpClient? client}); }
  class HomeController extends ChangeNotifier {
    HomeController(OpencodeApi? Function() api, {Duration debounce = const Duration(milliseconds: 300), DateTime Function()? now});
    List<SessionGroup> get groups;  // Today / Yesterday / This week / Older, each newest first
    String get query; void setQuery(String q); Future<void> refresh(); bool get loading; String? get error;
  }
  Uri chatUrl(Uri base, SessionInfo s);   // deep link into the web UI for that session
  class ChatSession extends ChangeNotifier { /* owns the server lifecycle for the app */
    ChatSession(RuntimeApi runtime, {required bool Function() isForeground});
    ServerSnapshot get snapshot; Uri? get base; int get generation; Future<void> ensureRunning(); Future<void> retry();
  }
  ```
  `HomeShell` has a `NavigationBar` (Home, Files, Terminal, Settings) in an `IndexedStack` and reports `runtime.setClients(1)` while the app is resumed and `setClients(0)` when paused or detached. Home shows: a search field, a "New session" button (project picker from `listProjects` plus "New project folder" which creates `/root/projects/<name>` through the file manager), and the grouped recent list. Tapping a session pushes `ChatPage`.

- [ ] **Step 1: Read the real API.** Start the server on the emulator, fetch `/doc` with Basic auth, and write the routes this task uses (list/search/create/rename/delete sessions, projects, how the project directory is passed, and the web UI route that opens a session) into `docs/opencode-api.md`. Adjust the interface above to match; if the server has no search parameter, `HttpOpencodeApi` filters client-side on title.
- [ ] **Step 2: Write failing tests:**
  - `opencode_api_test` (local fake `HttpServer`): sends Basic auth `opencode:<pw>`; `listSessions` parses the fixture JSON newest first and passes `search`/`limit`; `deleteSession` and `renameSession` hit the right method and path; a 401 throws `OpencodeApiException`; a non-JSON body throws `OpencodeApiException`, not `FormatException`.
  - `home_controller_test`: groups by Today/Yesterday/This week/Older using an injected `now`; an empty title shows as "Untitled session"; `setQuery('x')` triggers one `listSessions(search: 'x')` after the debounce, not one per keystroke; a failed refresh sets `error` and keeps the previous list; with the server not running (`api()` returns null) the list is empty and `error` is null.
  - `chat_session_test`: `attachesToRunningServer`, `startsWhenStopped`, `restartsAfterIdleStop` (only when `isForeground()`), `userStopIsNotRestarted`, `reloadsWhenPortOrPasswordChanges` (generation increments only on change), `failedExposesLogTail`; plus `chatUrl` for a session whose directory contains spaces and `/`.
- [ ] **Step 3:** Run `flutter test`. Expected: FAIL. **Step 4:** Implement. `ChatPage` keeps one `WebViewController` per `generation`, uses the navigation and auth rules from `server_guard.dart`, sends non-own-server `http(s)` links to the system browser (add `url_launcher`), and shows a progress view while `starting`/`restarting` and an error view with log and Retry on `failed`. Use `dart:io` `HttpClient` (no new dependency).
- [ ] **Step 5:** Run `flutter test` and `flutter analyze`. Expected: PASS and clean. **Step 6: Commit** `feat(app): opencode api client, home with history and search, chat page`.

### Task 7: Terminal tab

**Files:** Create `terminal/key_bytes.dart`, `terminal/extra_keys.dart`, `terminal/terminal_tab.dart`. Test: `key_bytes_test.dart`.

**Interfaces:**
- Produces:
  ```dart
  enum ExtraKey { esc, tab, up, down, left, right, home, end, pageUp, pageDown }
  Uint8List keyBytes(ExtraKey k, {bool ctrl = false});
  Uint8List ctrlChar(String ch);   // 'c' → 0x03, '[' → 0x1b, '@'..'_' / a..z map to 0..31; anything else → the char's own UTF-8 bytes
  ```
  `TerminalTab` keeps a list of sessions (tabs inside the tab). "+" opens a new one with `runtime.openTerminal(rows, cols)` using the `TerminalView`'s size. The sticky Ctrl button on the extra key row makes the next typed character go through `ctrlChar`. The terminal's `onResize` calls `session.resize` (never with 0 or negative values).

- [ ] **Step 1: Write failing tests (`key_bytes_test`):** `esc → [0x1b]`, `tab → [0x09]`, `up → ESC [ A`, `down → ESC [ B`, `right → ESC [ C`, `left → ESC [ D`, `home → ESC [ H`, `end → ESC [ F`, `pageUp → ESC [ 5 ~`, `pageDown → ESC [ 6 ~`, `ctrlChar('c') == [3]`, `ctrlChar('C') == [3]`, `ctrlChar('[') == [0x1b]`, `ctrlChar('1')` returns `'1'` unchanged.
- [ ] **Step 2:** Run. Expected: FAIL. **Step 3:** Implement the key functions, then the widgets with `xterm`'s `Terminal` and `TerminalView`. Pipe `session.output` into `terminal.write(utf8.decode(bytes, allowMalformed: true))`, and `terminal.onOutput` into `session.write`. Closing a tab calls `session.close()`. When the process exits, show "[process exited]" and a "Restart" button.
- [ ] **Step 4:** Run `flutter test` and `flutter analyze`. Expected: PASS and clean. **Step 5: Commit** `feat(app): terminal tab with extra keys`.

### Task 8: Files tab + Environment and Settings pages

**Files:** Create `files/files_tab.dart`, `files/file_editor_page.dart`, `files/files_controller.dart`, `settings/settings_tab.dart`, `environment/environment_page.dart`. Tests: `files_controller_test.dart`, `tabs_test.dart`.

**Interfaces:**
- Consumes: `RuntimeApi` file methods (Task 4), `environmentInfo()`, `resetEnvironment()`, `openTerminal(command:)`, `selfTest()`, `serverLog()`, `stopServer()`, `SettingsStore`.
- Produces `FilesController extends ChangeNotifier` (`FilesController(RuntimeApi)`: `path`, `entries`, `open(String dir)`, `up()`, `refresh()`, `createFolder`, `createFile`, `rename`, `delete`, `copy`, `move`, `selection` set with `toggle`, `paste()`, `error`).
- Behaviour:
  - Files tab: breadcrumb starting at `/root`; folders first, then files, alphabetical; long-press selects (multi-select delete/copy/move); "+" menu: new folder, new file; tap a text file opens `FileEditorPage` (monospace editor, Save); binary or >1 MB files show size only; "New session here" on a folder opens Chat in that directory.
  - Environment page: versions (node, python, opencode, arch), rootfs and `/root` sizes in MB, "Install build tools" runs `apk add build-base && echo build-base >> /root/.apk-extra` in the Terminal tab so every command is visible, "Reset environment" behind a confirm dialog that says `/root` is kept (calls `stopServer()`, then `resetEnvironment()`, then returns to Setup), and "Restore N extra packages" when `extraPackages` is not empty.
  - Settings tab: idle timeout (5, 15, 30, 60 min), OpenCode config (read and write `/root/.config/opencode/opencode.json` through the file manager; plain JSON editor with validation), an API-keys note ("keys are entered in the OpenCode chat screen; secure storage comes later"), Server log (bottom sheet), Stop server now, Environment, app version, `showLicensePage`.

- [ ] **Step 1: Write failing tests:** `files_controller_test`: opening a dir lists folders before files; `up()` at `/root` stays at `/root`; delete of a selection calls the runtime once per path and refreshes; an error from the runtime sets `error` and keeps the old listing. `tabs_test`: Settings idle choice persists and is sent to the runtime; reset asks for confirmation and does nothing on cancel; confirmed reset calls `stopServer` then `resetEnvironment` in that order; "Install build tools" opens a terminal with the apk command; invalid JSON in the config editor blocks Save.
- [ ] **Step 2:** Run. Expected: FAIL. **Step 3:** Implement. **Step 4:** Run `flutter test`. Expected: PASS. **Step 5: Commit** `feat(app): files manager, environment and settings`.

### Task 9: On-device verification + docs

**Files:** Modify `docs/spike-results.md` (or create `docs/phase3-4-results.md`) and `README.md`.

- [ ] **Step 1:** `bash tool/copy_rootfs.sh x86_64`, then `cd app && flutter run -d emulator-5554`. Walk through the flow and tick each item in the results doc:
  1. First run: onboarding → setup → home; the OpenCode tab loads the UI.
  2. Swipe the app from recents. `adb shell dumpsys activity services dev.opencodeapk.app` still lists `RuntimeService`, and the notification is shown. Reopen the app: it attaches to the same port and does not restart.
  3. Kill the server (`adb shell pkill -f opencode` from inside the app's terminal tab). The UI shows "restarting" and then the UI reloads on a new port.
  4. Set idle timeout to 1 min (via debug `setIdleMinutes`), background the app with no terminal open, and confirm the service stops after about 1 min. With a terminal open it does not stop.
  5. Terminal: `uname -m`, `vim`/`top` resize when rotating the device, `pip install requests` works.
  6. Environment: Install build tools shows `apk add` output. Reset keeps `/root/projects/*`.
  7. Notifications denied: the server still runs.
- [ ] **Step 2:** Update the README "Status" section: Phases 3–4 done, and what remains (Phase 2, 5, 6, and the real-phone check).
- [ ] **Step 3: Commit** `docs: phase 3-4 on-device results`.
