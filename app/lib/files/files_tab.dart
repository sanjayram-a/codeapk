import 'package:flutter/material.dart';
import 'package:opencode_runtime/opencode_runtime.dart';

import '../shell/shell_controller.dart';
import 'file_editor_page.dart';
import 'files_controller.dart';

/// Browse and manage the sandbox home (`/root`): folders, files, copy/move/delete, and a simple text editor.
class FilesTab extends StatefulWidget {
  const FilesTab({super.key, required this.runtime, required this.shell, required this.visible});

  final RuntimeApi runtime;
  final ShellController shell;
  final bool visible;

  @override
  State<FilesTab> createState() => _FilesTabState();
}

class _FilesTabState extends State<FilesTab> {
  late final FilesController _c = FilesController(widget.runtime);
  bool _loadedOnce = false;

  @override
  void initState() {
    super.initState();
    _maybeLoad();
  }

  @override
  void didUpdateWidget(FilesTab old) {
    super.didUpdateWidget(old);
    _maybeLoad();
    if (widget.visible && !old.visible) _c.refresh(); // files may have changed in chat or terminal
  }

  void _maybeLoad() {
    if (widget.visible && !_loadedOnce) {
      _loadedOnce = true;
      _c.open(FilesController.root);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<String?> _prompt(String title, {String initial = '', String action = 'OK'}) {
    final field = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: field, autofocus: true, onSubmitted: (v) => Navigator.pop(ctx, v)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, field.text), child: Text(action)),
        ],
      ),
    );
  }

  Future<void> _open(FileEntry e) async {
    if (_c.selection.isNotEmpty) return _c.toggle(e.path);
    if (e.isDir) return _c.open(e.path);
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => FileEditorPage(runtime: widget.runtime, path: e.path)),
    );
    if (saved == true) _c.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListenableBuilder(
        listenable: _c,
        builder: (context, _) {
          final selecting = _c.selection.isNotEmpty;
          return PopScope(
            canPop: !(_c.canGoUp && widget.visible) && !selecting,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) return;
              selecting ? _c.clearSelection() : _c.up();
            },
            child: Scaffold(
              backgroundColor: Colors.transparent,
              appBar: AppBar(
                leading: selecting
                    ? IconButton(icon: const Icon(Icons.close), onPressed: _c.clearSelection)
                    : (_c.canGoUp ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: _c.up) : null),
                title: Text(selecting ? '${_c.selection.length} selected' : 'Files'),
                actions: selecting ? _selectionActions() : _normalActions(),
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(44),
                  child: _Breadcrumbs(controller: _c),
                ),
              ),
              floatingActionButton: selecting
                  ? null
                  : PopupMenuButton<String>(
                      tooltip: 'Add',
                      onSelected: (v) async {
                        if (v == 'folder') {
                          final n = await _prompt('New folder', action: 'Create');
                          if (n != null) await _c.createFolder(n);
                        } else if (v == 'file') {
                          final n = await _prompt('New file', action: 'Create');
                          if (n != null) await _c.createFile(n);
                        } else if (v == 'paste') {
                          await _c.paste();
                        } else if (v == 'session') {
                          widget.shell.openChat?.call(directory: _c.path);
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'folder', child: Text('New folder')),
                        const PopupMenuItem(value: 'file', child: Text('New file')),
                        if (_c.hasClipboard) const PopupMenuItem(value: 'paste', child: Text('Paste here')),
                        const PopupMenuItem(value: 'session', child: Text('New session here')),
                      ],
                      child: const FloatingActionButton(onPressed: null, child: Icon(Icons.add)),
                    ),
              body: Column(
                children: [
                  if (_c.error != null)
                    MaterialBanner(
                      content: Text(_c.error!),
                      actions: [TextButton(onPressed: _c.refresh, child: const Text('Dismiss'))],
                    ),
                  Expanded(child: _body(context)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _normalActions() => [
        if (_c.hasClipboard) IconButton(icon: const Icon(Icons.content_paste), tooltip: 'Paste here', onPressed: _c.paste),
        IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh', onPressed: _c.refresh),
      ];

  List<Widget> _selectionActions() {
    final single = _c.selection.length == 1
        ? _c.entries.where((e) => e.path == _c.selection.first).cast<FileEntry?>().firstOrNull
        : null;
    return [
      if (single != null)
        IconButton(
          icon: const Icon(Icons.drive_file_rename_outline),
          tooltip: 'Rename',
          onPressed: () async {
            final n = await _prompt('Rename', initial: single.name, action: 'Rename');
            _c.clearSelection();
            if (n != null) await _c.rename(single, n);
          },
        ),
      IconButton(icon: const Icon(Icons.copy), tooltip: 'Copy', onPressed: _c.copySelection),
      IconButton(icon: const Icon(Icons.content_cut), tooltip: 'Cut', onPressed: _c.cutSelection),
      IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: 'Delete',
        onPressed: () async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text('Delete ${_c.selection.length} item(s)?'),
              content: const Text('Folders are deleted with everything inside. This cannot be undone.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
              ],
            ),
          );
          if (ok == true) await _c.deleteSelection();
        },
      ),
    ];
  }

  Widget _body(BuildContext context) {
    if (_c.loading && _c.entries.isEmpty) return const Center(child: CircularProgressIndicator());
    if (_c.entries.isEmpty) {
      return const Center(child: Text('This folder is empty'));
    }
    return RefreshIndicator(
      onRefresh: _c.refresh,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 88),
        itemCount: _c.entries.length,
        itemBuilder: (context, i) {
          final e = _c.entries[i];
          final selected = _c.selection.contains(e.path);
          return ListTile(
            selected: selected,
            leading: Icon(selected ? Icons.check_circle : (e.isDir ? Icons.folder : _iconFor(e.name))),
            title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(e.isDir ? 'Folder' : _size(e.size)),
            onTap: () => _open(e),
            onLongPress: () => _c.toggle(e.path),
          );
        },
      ),
    );
  }

  IconData _iconFor(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.md') || n.endsWith('.txt')) return Icons.description_outlined;
    if (n.endsWith('.json') || n.endsWith('.yaml') || n.endsWith('.yml') || n.endsWith('.toml')) return Icons.data_object;
    if (n.endsWith('.py') || n.endsWith('.js') || n.endsWith('.ts') || n.endsWith('.sh') || n.endsWith('.dart')) {
      return Icons.code;
    }
    return Icons.insert_drive_file_outlined;
  }

  String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _Breadcrumbs extends StatelessWidget {
  const _Breadcrumbs({required this.controller});

  final FilesController controller;

  @override
  Widget build(BuildContext context) {
    final crumbs = controller.crumbs;
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        reverse: true, // keeps the current folder visible on narrow screens
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: crumbs.length,
        separatorBuilder: (_, _) => const Icon(Icons.chevron_right, size: 18),
        itemBuilder: (context, i) {
          final c = crumbs[crumbs.length - 1 - i];
          return Center(
            child: ActionChip(
              visualDensity: VisualDensity.compact,
              label: Text(c.$1),
              onPressed: () => controller.open(c.$2),
            ),
          );
        },
      ),
    );
  }
}
