import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:opencode_runtime/opencode_runtime.dart';

/// Runs one fixed command in the sandbox and shows its output. Read-only: no
/// text input, no extra keys and no terminal tab.
class CommandTaskPage extends StatefulWidget {
  const CommandTaskPage({
    super.key,
    required this.runtime,
    required this.title,
    required this.command,
  });

  final RuntimeApi runtime;
  final String title;
  final List<String> command;

  @override
  State<CommandTaskPage> createState() => _CommandTaskPageState();
}

class _CommandTaskPageState extends State<CommandTaskPage> {
  final _log = StringBuffer();
  bool _done = false;
  bool _failed = false;
  bool _allowPop = false;
  TerminalSession? _session;
  StreamSubscription<String>? _sub;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final session = await widget.runtime.openTerminal(
        rows: 24,
        cols: 80,
        command: widget.command,
      );
      if (!mounted) {
        unawaited(session.close());
        return;
      }
      _session = session;
      _sub = session.output
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(
            (text) {
              if (mounted) setState(() => _log.write(text));
            },
            onDone: () {
              if (mounted) setState(() => _done = true);
            },
            onError: (Object error) {
              if (mounted) {
                setState(() {
                  _log.writeln(error);
                  _done = true;
                  _failed = true;
                });
              }
            },
          );
    } catch (e) {
      if (mounted) {
        setState(() {
          _log.writeln(e);
          _done = true;
          _failed = true;
        });
      }
    }
  }

  Future<void> _requestClose() async {
    if (_done) {
      Navigator.of(context).pop();
      return;
    }
    final stop = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stop this task?'),
        content: const Text(
          'The command will be stopped and may be left half-finished.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep running'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
    if (stop != true || !mounted) return;
    setState(() => _allowPop = true);
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    unawaited(_session?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: _done || _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        unawaited(_requestClose());
      },
      child: Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'This runs without a terminal. The output is read-only.',
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                reverse: true,
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  _log.isEmpty ? 'Starting…' : _log.toString(),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
            _footer(context),
          ],
        ),
      ),
    );
  }

  Widget _footer(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (!_done) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.hourglass_top),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Running… This can take a few minutes.'),
            ),
            TextButton(
              onPressed: () => unawaited(_requestClose()),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_failed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'The task failed. See the output above.',
                style: TextStyle(color: scheme.error),
              ),
            ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}
