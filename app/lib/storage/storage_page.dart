import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:opencode_runtime/opencode_runtime.dart';

import '../format.dart';
import '../pro/paywall_page.dart';
import '../pro/pro_controller.dart';
import '../pro/pro_feature.dart';

/// Package caches (npm, Python) with a Clear button each, and the size of every project folder.
/// Sizes can take a while to add up, so a spinner is shown until they are ready.
class StoragePage extends StatefulWidget {
  const StoragePage({super.key, required this.runtime, required this.pro});

  final RuntimeApi runtime;
  final ProController pro;

  @override
  State<StoragePage> createState() => _StoragePageState();
}

class _StoragePageState extends State<StoragePage> {
  StorageInfo? _info;
  Object? _error;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _info = null;
      _error = null;
    });
    try {
      final info = await widget.runtime.storageInfo();
      if (mounted) setState(() => _info = info);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _clear(List<CacheKind> kinds) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _clearing = true);
    var freed = 0;
    try {
      for (final k in kinds) {
        freed += await widget.runtime.clearCache(k);
      }
      messenger.showSnackBar(
        SnackBar(content: Text('Freed ${formatBytes(freed)}')),
      );
    } on PlatformException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message ?? e.code)));
    }
    if (!mounted) return;
    setState(() => _clearing = false);
    final info = await widget.runtime.storageInfo();
    if (mounted) setState(() => _info = info);
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return ListenableBuilder(
      listenable: widget.pro,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Storage & cache'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: info == null ? null : _load,
            ),
          ],
        ),
        body: _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('$_error'),
                ),
              )
            : info == null
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Calculating storage…'),
                  ],
                ),
              )
            : ListView(
                children: [
                  const _Section('Package caches'),
                  _CacheTile(
                    icon: Icons.javascript,
                    title: 'npm cache',
                    bytes: info.npmBytes,
                    busy: _clearing,
                    onClear: () => _clear([CacheKind.npm]),
                  ),
                  _CacheTile(
                    icon: Icons.code,
                    title: 'Python cache (pip, uv)',
                    bytes: info.pythonBytes,
                    busy: _clearing,
                    onClear: () => _clear([CacheKind.python]),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.tonal(
                        onPressed:
                            _clearing ||
                                (info.npmBytes == 0 && info.pythonBytes == 0)
                            ? null
                            : () => _clear([CacheKind.npm, CacheKind.python]),
                        child: const Text('Clear all caches'),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      'Only downloaded packages are removed. Your projects are not touched.',
                    ),
                  ),
                  const _Section('Projects'),
                  if (!widget.pro.isPro)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.lock_outline,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Project size breakdown is a Pro feature',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'See how much space each project uses.',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            FilledButton.tonal(
                              onPressed: () => showPaywall(
                                context,
                                widget.pro,
                                ProFeature.projectSizes,
                              ),
                              child: const Text('Unlock Pro'),
                            ),
                          ],
                        ),
                      ),
                    )
                  else ...[
                    if (info.projects.isEmpty)
                      const ListTile(
                        title: Text('No projects yet'),
                        subtitle: Text(
                          'Folders in /root/projects appear here.',
                        ),
                      ),
                    for (final p in info.projects)
                      ListTile(
                        leading: const Icon(Icons.folder_outlined),
                        title: Text(
                          p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Text(formatBytes(p.bytes)),
                      ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _CacheTile extends StatelessWidget {
  const _CacheTile({
    required this.icon,
    required this.title,
    required this.bytes,
    required this.busy,
    required this.onClear,
  });

  final IconData icon;
  final String title;
  final int bytes;
  final bool busy;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(formatBytes(bytes)),
    trailing: TextButton(
      onPressed: busy || bytes == 0 ? null : onClear,
      child: const Text('Clear'),
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}
