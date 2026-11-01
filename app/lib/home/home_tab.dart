import 'package:flutter/material.dart';
import 'package:opencode_runtime/opencode_runtime.dart';

import '../api/session.dart';
import '../chat/chat_session.dart';
import '../shell/shell_controller.dart';
import 'home_controller.dart';

/// Recent sessions grouped by day, with search; tap one to resume it in the chat.
class HomeTab extends StatefulWidget {
  const HomeTab({super.key, required this.controller, required this.chat, required this.shell, required this.runtime});

  final HomeController controller;
  final ChatSession chat;
  final ShellController shell;
  final RuntimeApi runtime;

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _newSession() async {
    final dir = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _NewSessionSheet(
        directories: widget.controller.knownDirectories(),
        createFolder: (name) async {
          final path = '/root/projects/$name';
          await widget.runtime.createFolder(path);
          return path;
        },
      ),
    );
    if (dir != null) await widget.shell.openChat?.call(directory: dir);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListenableBuilder(
        listenable: Listenable.merge([widget.controller, widget.chat]),
        builder: (context, _) {
          final c = widget.controller;
          final snap = widget.chat.snapshot;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: SearchBar(
                  controller: _search,
                  hintText: 'Search sessions',
                  leading: const Icon(Icons.search),
                  trailing: [
                    if (c.query.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Clear search',
                        onPressed: () {
                          _search.clear();
                          c.setQuery('');
                        },
                      ),
                  ],
                  onChanged: c.setQuery,
                  elevation: const WidgetStatePropertyAll(0),
                ),
              ),
              if (!snap.isRunning) _ServerBanner(chat: widget.chat),
              if (c.error != null && snap.isRunning)
                MaterialBanner(
                  content: Text(c.error!),
                  actions: [TextButton(onPressed: c.refresh, child: const Text('Retry'))],
                ),
              Expanded(child: _list(context, c, snap)),
            ],
          );
        },
      ),
    );
  }

  Widget _list(BuildContext context, HomeController c, ServerSnapshot snap) {
    if (snap.isRunning && c.loading && !c.hasSessions) {
      return const Center(child: CircularProgressIndicator());
    }
    final groups = c.groups;
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: c.refresh,
          child: groups.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    const SizedBox(height: 80),
                    Icon(Icons.forum_outlined, size: 48, color: Theme.of(context).colorScheme.outline),
                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        c.query.isNotEmpty ? 'No sessions match "${c.query}"' : 'No sessions yet',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (c.query.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(8),
                        child: Center(child: Text('Start one with the button below.')),
                      ),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 96),
                  children: [
                    for (final g in groups) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                        child: Text(g.label, style: Theme.of(context).textTheme.labelLarge),
                      ),
                      for (final s in g.sessions) _SessionTile(session: s, controller: c, shell: widget.shell),
                    ],
                  ],
                ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: snap.isRunning ? _newSession : null,
            icon: const Icon(Icons.add),
            label: const Text('New session'),
          ),
        ),
      ],
    );
  }
}

class _ServerBanner extends StatelessWidget {
  const _ServerBanner({required this.chat});

  final ChatSession chat;

  @override
  Widget build(BuildContext context) {
    final s = chat.snapshot;
    final busy = s.status == ServerStatus.starting || s.status == ServerStatus.restarting;
    final (text, action) = switch (s.status) {
      ServerStatus.starting => ('Starting the OpenCode server…', null),
      ServerStatus.restarting => ('The server stopped unexpectedly — restarting…', null),
      ServerStatus.failed => ('The server could not start: ${s.error ?? 'unknown error'}', 'Retry'),
      _ => ('The OpenCode server is stopped.', 'Start'),
    };
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            if (busy)
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            Expanded(child: Text(text)),
            if (action != null) TextButton(onPressed: chat.retry, child: Text(action)),
          ],
        ),
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session, required this.controller, required this.shell});

  final SessionInfo session;
  final HomeController controller;
  final ShellController shell;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(session.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${_folder(session.directory)} · ${_ago(session.updated)}', maxLines: 1, overflow: TextOverflow.ellipsis),
      leading: const CircleAvatar(child: Icon(Icons.chat_bubble_outline, size: 20)),
      onTap: () => shell.openChat?.call(session: session),
      trailing: PopupMenuButton<String>(
        onSelected: (v) async {
          if (v == 'rename') {
            final name = await _askName(context, session.displayTitle);
            if (name != null && name.trim().isNotEmpty) await controller.rename(session, name.trim());
          } else if (v == 'delete') {
            final ok = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Delete this session?'),
                content: Text('"${session.displayTitle}" and its messages will be removed. Files it created stay.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                  FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
                ],
              ),
            );
            if (ok == true) await controller.delete(session);
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'rename', child: Text('Rename')),
          PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }

  static String _folder(String? dir) {
    if (dir == null || dir.isEmpty) return 'Home';
    if (dir == '/root') return 'Home';
    return dir.startsWith('/root/') ? dir.substring('/root/'.length) : dir;
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    if (d.inDays < 7) return '${d.inDays} d ago';
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }
}

Future<String?> _askName(BuildContext context, String initial) {
  final field = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Rename session'),
      content: TextField(controller: field, autofocus: true, onSubmitted: (v) => Navigator.pop(context, v)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, field.text), child: const Text('Rename')),
      ],
    ),
  );
}

/// Pick where a new session starts: an existing folder, or a new project folder under /root/projects.
class _NewSessionSheet extends StatefulWidget {
  const _NewSessionSheet({required this.directories, required this.createFolder});

  final Future<List<String>> directories;
  final Future<String> Function(String name) createFolder;

  @override
  State<_NewSessionSheet> createState() => _NewSessionSheetState();
}

class _NewSessionSheetState extends State<_NewSessionSheet> {
  final _name = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final n = _name.text.trim();
    if (n.isEmpty || n.contains('/') || n == '.' || n == '..') {
      setState(() => _error = 'Use a simple folder name, without "/".');
      return;
    }
    try {
      final path = await widget.createFolder(n);
      if (mounted) Navigator.pop(context, path);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text('New session', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              decoration: InputDecoration(
                labelText: 'New project folder',
                hintText: 'my-app',
                errorText: _error,
                suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), tooltip: 'Create and start', onPressed: _create),
              ),
              onSubmitted: (_) => _create(),
            ),
            const SizedBox(height: 16),
            Text('Or work in an existing folder', style: Theme.of(context).textTheme.labelLarge),
            FutureBuilder<List<String>>(
              future: widget.directories,
              builder: (context, snap) {
                if (!snap.hasData) return const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator());
                return Column(
                  children: [
                    for (final d in snap.data!)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.folder_outlined),
                        title: Text(d == '/root' ? 'Home (/root)' : d),
                        onTap: () => Navigator.pop(context, d),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
