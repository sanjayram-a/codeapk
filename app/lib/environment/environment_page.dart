import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:opencode_runtime/opencode_runtime.dart';

import '../shell/shell_controller.dart';

const buildToolsCommand = ['/bin/sh', '-c', 'apk add build-base && echo build-base >> /root/.apk-extra'];
const restoreExtrasCommand = ['/bin/sh', '-c', r'apk add $(cat /root/.apk-extra)'];

/// What is installed, how much space it uses, one-tap extras (shown in the Terminal so every command is visible),
/// and "reset environment" which keeps `/root`.
class EnvironmentPage extends StatefulWidget {
  const EnvironmentPage({super.key, required this.runtime, required this.shell, required this.onResetDone});

  final RuntimeApi runtime;
  final ShellController shell;
  final VoidCallback onResetDone;

  @override
  State<EnvironmentPage> createState() => _EnvironmentPageState();
}

class _EnvironmentPageState extends State<EnvironmentPage> {
  late Future<(EnvironmentInfo, Map<String, String>)> _load = _fetch();

  Future<(EnvironmentInfo, Map<String, String>)> _fetch() async {
    final info = await widget.runtime.environmentInfo();
    Map<String, String> versions = const {};
    try {
      versions = await widget.runtime.selfTest();
    } catch (_) {
      // versions are informational; sizes are still useful
    }
    return (info, versions);
  }

  void _runInTerminal(List<String> command) {
    widget.shell.runInTerminal(command);
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _reset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset the Linux environment?'),
        content: const Text(
          'The Linux system is deleted and unpacked again. Your files in /root (projects, OpenCode settings and '
          'sessions) are kept. Anything you installed with apk must be installed again.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reset')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.shell.closeAllTerminals?.call();
      await widget.runtime.stopServer();
      await widget.runtime.resetEnvironment();
    } on PlatformException catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(e.code == 'busy' ? 'Close running terminals first.' : (e.message ?? e.code)),
      ));
      return;
    }
    navigator.popUntil((r) => r.isFirst);
    widget.onResetDone();
  }

  String _mb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(bytes < 10 * 1024 * 1024 ? 1 : 0)} MB';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Linux environment'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh', onPressed: () => setState(() => _load = _fetch())),
        ],
      ),
      body: FutureBuilder(
        future: _load,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final (info, versions) = snap.data!;
          return ListView(
            children: [
              for (final e in {'arch': 'CPU', 'node': 'Node.js', 'python': 'Python', 'opencode': 'OpenCode'}.entries)
                ListTile(
                  dense: true,
                  title: Text(e.value),
                  trailing: Text(versions[e.key] ?? '—'),
                ),
              ListTile(dense: true, title: const Text('System image'), trailing: Text(info.rootfsVersion ?? 'not installed')),
              ListTile(dense: true, title: const Text('Linux system size'), trailing: Text(_mb(info.rootfsBytes))),
              ListTile(dense: true, title: const Text('Your files (/root)'), trailing: Text(_mb(info.homeBytes))),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.build_outlined),
                title: const Text('Install build tools'),
                subtitle: const Text('gcc, make and headers (apk add build-base) — about 200 MB'),
                onTap: () => _runInTerminal(buildToolsCommand),
              ),
              if (info.extraPackages.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.restore),
                  title: Text('Restore ${info.extraPackages.length} extra package(s)'),
                  subtitle: Text(info.extraPackages.join(', ')),
                  onTap: () => _runInTerminal(restoreExtrasCommand),
                ),
              ListTile(
                leading: Icon(Icons.restart_alt, color: Theme.of(context).colorScheme.error),
                title: const Text('Reset environment'),
                subtitle: const Text('Keeps everything in /root'),
                onTap: _reset,
              ),
            ],
          );
        },
      ),
    );
  }
}
