import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:opencode_runtime/opencode_runtime.dart';

import '../app_deps.dart';
import '../chat/chat_session.dart';
import '../environment/environment_page.dart';
import '../files/file_editor_page.dart';
import '../shell/shell_controller.dart';
import '../storage/storage_page.dart';

const opencodeConfigPath = '/root/.config/opencode/opencode.json';
const _configTemplate = '{\n  "\$schema": "https://opencode.ai/config.json"\n}\n';
const appVersion = '1.0.0';

/// Null when [text] is a JSON object, otherwise a short message saying what is wrong.
String? validateConfigJson(String text) {
  try {
    final v = jsonDecode(text);
    return v is Map ? null : 'The config must be a JSON object ({ … }).';
  } on FormatException catch (e) {
    return 'Invalid JSON: ${e.message}';
  }
}

class SettingsTab extends StatefulWidget {
  const SettingsTab({
    super.key,
    required this.deps,
    required this.chat,
    required this.shell,
    required this.onResetDone,
  });

  final AppDeps deps;
  final ChatSession chat;
  final ShellController shell;
  final VoidCallback onResetDone;

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  static const idleChoices = [5, 15, 30, 60];

  RuntimeApi get _rt => widget.deps.runtime;
  late int _idle = widget.deps.settings.idleMinutes;

  Future<void> _setIdle(int minutes) async {
    setState(() => _idle = minutes);
    await widget.deps.settings.setIdleMinutes(minutes);
    await _rt.setIdleTimeoutMinutes(minutes);
  }

  Future<void> _showLog() async {
    final log = await _rt.serverLog();
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.7,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            reverse: true,
            child: SelectableText(
              log.isEmpty ? '(empty)' : log,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openConfig() async {
    try {
      await _rt.readText(opencodeConfigPath);
    } on PlatformException catch (e) {
      if (e.message?.startsWith('not found') == true) {
        await _rt.writeText(opencodeConfigPath, _configTemplate);
      }
    }
    if (!mounted) return;
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => FileEditorPage(runtime: _rt, path: opencodeConfigPath, validate: validateConfigJson),
    ));
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Saved. Restart the server for changes to apply.'),
        action: SnackBarAction(label: 'Restart', onPressed: _restart),
      ));
    }
  }

  Future<void> _restart() async {
    await _rt.stopServer();
    await widget.chat.ensureRunning();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListenableBuilder(
        listenable: widget.chat,
        builder: (context, _) {
          final s = widget.chat.snapshot;
          return Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(title: const Text('Settings')),
            body: ListView(
              children: [
                const _Section('Server'),
                ListTile(
                  leading: Icon(s.isRunning ? Icons.circle : Icons.circle_outlined,
                      color: s.isRunning ? Colors.green : null, size: 16),
                  title: Text(_statusText(s)),
                  trailing: s.isRunning
                      ? TextButton(onPressed: _rt.stopServer, child: const Text('Stop'))
                      : (s.status == ServerStatus.starting || s.status == ServerStatus.restarting)
                          ? null
                          : TextButton(onPressed: widget.chat.retry, child: const Text('Start')),
                ),
                ListTile(
                  leading: const Icon(Icons.timer_outlined),
                  title: const Text('Stop the server when idle'),
                  subtitle: const Text('After this long with the app closed and nothing running'),
                  trailing: DropdownButton<int>(
                    value: idleChoices.contains(_idle) ? _idle : null,
                    hint: Text('$_idle min'),
                    items: [for (final m in idleChoices) DropdownMenuItem(value: m, child: Text('$m min'))],
                    onChanged: (v) => v == null ? null : _setIdle(v),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.article_outlined),
                  title: const Text('Server log'),
                  onTap: _showLog,
                ),
                const _Section('OpenCode'),
                ListTile(
                  leading: const Icon(Icons.tune),
                  title: const Text('Config file'),
                  subtitle: const Text('opencode.json — default model, providers, permissions'),
                  onTap: _openConfig,
                ),
                const ListTile(
                  leading: Icon(Icons.key),
                  title: Text('Provider API keys'),
                  subtitle: Text(
                    'Open a chat and use OpenCode’s own provider login. Keys stay inside the app’s private storage.',
                  ),
                ),
                const _Section('System'),
                ListTile(
                  leading: const Icon(Icons.developer_board),
                  title: const Text('Linux environment'),
                  subtitle: const Text('Versions, storage, build tools, reset'),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => EnvironmentPage(
                      runtime: _rt,
                      shell: widget.shell,
                      onResetDone: widget.onResetDone,
                    ),
                  )),
                ),
                ListTile(
                  leading: const Icon(Icons.storage),
                  title: const Text('Storage & cache'),
                  subtitle: const Text('npm and Python cache, size of each project'),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => StoragePage(runtime: _rt),
                  )),
                ),
                const _Section('About'),
                const ListTile(leading: Icon(Icons.info_outline), title: Text('OpenCode for Android'), subtitle: Text('Version $appVersion')),
                ListTile(
                  leading: const Icon(Icons.gavel),
                  title: const Text('Open-source licenses'),
                  onTap: () => showLicensePage(context: context, applicationName: 'OpenCode for Android', applicationVersion: appVersion),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _statusText(ServerSnapshot s) => switch (s.status) {
        ServerStatus.running => 'Server running',
        ServerStatus.starting => 'Server starting…',
        ServerStatus.restarting => 'Server restarting…',
        ServerStatus.failed => 'Server failed: ${s.error ?? 'unknown error'}',
        ServerStatus.stopped => s.stopReason == 'idle' ? 'Server stopped (idle)' : 'Server stopped',
      };
}

class _Section extends StatelessWidget {
  const _Section(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}
