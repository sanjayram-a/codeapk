import 'package:flutter/material.dart';

import '../api/opencode_api.dart';
import '../app_deps.dart';
import '../chat/chat_page.dart';
import '../chat/chat_session.dart';
import '../files/files_tab.dart';
import '../home/home_controller.dart';
import '../home/home_tab.dart';
import '../settings/settings_tab.dart';
import '../terminal/terminal_tab.dart';
import 'shell_controller.dart';

/// The signed-in app: Home, Files, Terminal and Settings tabs. Chat opens full-screen on top.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.deps, required this.onResetDone});

  final AppDeps deps;
  final VoidCallback onResetDone;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  late final ShellController _shell = ShellController()..addListener(_rebuild);
  late final ChatSession _chat = ChatSession(widget.deps.runtime, isForeground: () => _resumed);
  late final HomeController _home;
  bool _resumed = true;
  OpencodeApi? _api;
  int _apiGeneration = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final rt = widget.deps.runtime;
    rt.setClients(1);
    rt.setIdleTimeoutMinutes(widget.deps.settings.idleMinutes);
    _home = HomeController(api: _currentApi, extraDirectories: _projectFolders);
    _shell.openChat = _openChat;
    _chat.addListener(_onChat);
    _chat.ensureRunning();
  }

  /// The API client for the running server; a new one whenever the server's port/password changed.
  OpencodeApi? _currentApi() {
    final base = _chat.base;
    final password = _chat.password;
    if (base == null || password == null) return null;
    if (_apiGeneration != _chat.generation || _api == null) {
      _api = widget.deps.apiFactory(base, password);
      _apiGeneration = _chat.generation;
    }
    return _api;
  }

  Future<List<String>> _projectFolders() async {
    final entries = await widget.deps.runtime.listFiles('/root/projects');
    return [for (final e in entries) if (e.isDir) e.path];
  }

  void _onChat() {
    if (_chat.snapshot.isRunning) _home.refresh();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  Future<void> _openChat({SessionInfo? session, String? directory}) async {
    final api = _currentApi();
    final navigator = Navigator.of(context);
    var target = session;
    if (target == null) {
      if (api == null) return;
      try {
        target = await api.createSession(directory: directory ?? '/root');
      } on OpencodeApiException catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
        return;
      }
    }
    if (!mounted) return;
    await navigator.push(MaterialPageRoute<void>(builder: (_) => ChatPage(chat: _chat, session: target!)));
    if (mounted) _home.refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    _resumed = resumed;
    widget.deps.runtime.setClients(resumed ? 1 : 0);
    if (resumed) _chat.onForeground();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _chat.removeListener(_onChat);
    _shell.removeListener(_rebuild);
    _home.dispose();
    _chat.dispose();
    _shell.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _shell.tab,
        children: [
          HomeTab(controller: _home, chat: _chat, shell: _shell, runtime: widget.deps.runtime),
          FilesTab(runtime: widget.deps.runtime, shell: _shell, visible: _shell.tab == ShellController.filesTab),
          TerminalTab(runtime: widget.deps.runtime, shell: _shell, visible: _shell.tab == ShellController.terminalTab),
          SettingsTab(
            deps: widget.deps,
            chat: _chat,
            shell: _shell,
            onResetDone: widget.onResetDone,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _shell.tab,
        onDestinationSelected: _shell.select,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder), label: 'Files'),
          NavigationDestination(icon: Icon(Icons.terminal), label: 'Terminal'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
