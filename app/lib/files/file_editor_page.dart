import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:opencode_runtime/opencode_runtime.dart';

/// Plain text editor for one file in the sandbox home. Pops with `true` when something was saved.
class FileEditorPage extends StatefulWidget {
  const FileEditorPage({super.key, required this.runtime, required this.path, this.validate});

  final RuntimeApi runtime;
  final String path;

  /// Returns an error message when the text may not be saved (for example invalid JSON), or null when it is fine.
  final String? Function(String text)? validate;

  @override
  State<FileEditorPage> createState() => _FileEditorPageState();
}

class _FileEditorPageState extends State<FileEditorPage> {
  final _text = TextEditingController();
  String _original = '';
  bool _loading = true;
  String? _loadError;
  bool _saved = false;
  bool _saving = false;

  bool get _dirty => _text.text != _original;
  String? get _invalid => widget.validate?.call(_text.text);

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
    _load();
  }

  Future<void> _load() async {
    try {
      final t = await widget.runtime.readText(widget.path);
      _original = t;
      _text.text = t;
    } on PlatformException catch (e) {
      _loadError = e.code == 'invalid'
          ? 'This file is too large or is not a text file, so it cannot be edited here.'
          : (e.message ?? e.code);
    } catch (e) {
      _loadError = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.runtime.writeText(widget.path, _text.text);
      _original = _text.text;
      _saved = true;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
    } on PlatformException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? e.code)));
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _download() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.runtime.saveToDownloads(widget.path);
      messenger.showSnackBar(const SnackBar(content: Text('Saved to Downloads')));
    } on PlatformException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message ?? e.code)));
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.path.split('/').last;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final discard = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Discard changes?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep editing')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard')),
            ],
          ),
        );
        if (discard == true) navigator.pop(_saved);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(name, overflow: TextOverflow.ellipsis),
          actions: [
            TextButton(
              onPressed: (!_dirty || _invalid != null || _saving || _loadError != null) ? null : _save,
              child: const Text('Save'),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_loadError!, textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _download,
                            icon: const Icon(Icons.download),
                            label: const Text('Save to Downloads'),
                          ),
                        ],
                      ),
                    ),
                  )
                : Column(
                    children: [
                      if (_invalid != null)
                        MaterialBanner(content: Text(_invalid!), actions: const [SizedBox.shrink()]),
                      Expanded(
                        child: TextField(
                          controller: _text,
                          expands: true,
                          maxLines: null,
                          minLines: null,
                          textAlignVertical: TextAlignVertical.top,
                          keyboardType: TextInputType.multiline,
                          autocorrect: false,
                          enableSuggestions: false,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                          decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.all(12)),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}
