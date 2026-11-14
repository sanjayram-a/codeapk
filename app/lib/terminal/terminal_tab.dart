import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:opencode_runtime/opencode_runtime.dart';
import 'package:xterm/xterm.dart';

import '../pro/paywall_page.dart';
import '../pro/pro_controller.dart';
import '../pro/pro_feature.dart';
import '../shell/shell_controller.dart';
import 'ctrl_keys.dart';
import 'extra_keys.dart';

/// Several shells in the sandbox (and one-off commands such as `apk add`), with an extra key row.
class TerminalTab extends StatefulWidget {
  const TerminalTab({
    super.key,
    required this.runtime,
    required this.shell,
    required this.visible,
    required this.pro,
  });

  final RuntimeApi runtime;
  final ShellController shell;
  final bool visible;
  final ProController pro;

  @override
  State<TerminalTab> createState() => _TerminalTabState();
}

class _Tab {
  _Tab(this.title, this.command, this.terminal);

  final String title;
  final List<String>? command;
  final Terminal terminal;
  TerminalSession? session;
  StreamSubscription<String>? sub;
  bool exited = false;
  String? error;
}

class _TerminalTabState extends State<TerminalTab> {
  final _tabs = <_Tab>[];
  final _ctrl = CtrlState();
  int _current = 0;
  int _counter = 0;

  @override
  void initState() {
    super.initState();
    widget.shell.closeAllTerminals = _closeAll;
    widget.shell.addListener(_onShell);
    widget.pro.addListener(_onPro);
    _onShell();
  }

  @override
  void didUpdateWidget(TerminalTab old) {
    super.didUpdateWidget(old);
    if (old.pro != widget.pro) {
      old.pro.removeListener(_onPro);
      widget.pro.addListener(_onPro);
    }
    _onShell();
  }

  void _onPro() {
    if (!widget.pro.isPro) unawaited(_closeAll());
    if (mounted) setState(() {});
  }

  /// Open the first shell lazily (starting proot is not free) and run commands other tabs asked for.
  void _onShell() {
    if (!widget.pro.isPro) return;
    if (!widget.visible) return;
    final cmd = widget.shell.takePendingCommand();
    if (cmd != null) {
      _open(
        command: cmd,
        title: cmd.last.length > 18
            ? '${cmd.last.substring(0, 18)}…'
            : cmd.last,
      );
    } else if (_tabs.isEmpty) {
      _open();
    }
  }

  Future<void> _open({List<String>? command, String? title}) async {
    if (!widget.pro.isPro) return;
    final tab = _Tab(
      title ?? 'Shell ${++_counter}',
      command,
      Terminal(maxLines: 10000),
    );
    setState(() {
      _tabs.add(tab);
      _current = _tabs.length - 1;
    });
    await _start(tab);
  }

  Future<void> _start(_Tab tab) async {
    tab.exited = false;
    tab.error = null;
    try {
      final session = await widget.runtime.openTerminal(
        rows: 24,
        cols: 80,
        command: tab.command,
      );
      tab.session = session;
      tab.terminal.onOutput = (data) => session.write(_ctrl.encode(data));
      tab.terminal.onResize = (w, h, _, _) {
        if (w > 0 && h > 0) session.resize(h, w);
      };
      // Terminal.write wants text; decode the byte stream incrementally so a multi-byte character split across
      // chunks is not mangled.
      tab.sub = session.output
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(
            tab.terminal.write,
            onDone: () {
              tab.exited = true;
              tab.terminal.write('\r\n[process exited]\r\n');
              if (mounted) setState(() {});
            },
          );
      if (tab.terminal.viewWidth > 0) {
        session.resize(tab.terminal.viewHeight, tab.terminal.viewWidth);
      }
    } catch (e) {
      tab.error = e.toString();
    }
    if (mounted) setState(() {});
  }

  Future<void> _closeTab(int i) async {
    final tab = _tabs.removeAt(i);
    await tab.sub?.cancel();
    await tab.session?.close();
    setState(
      () => _current = _current.clamp(0, _tabs.isEmpty ? 0 : _tabs.length - 1),
    );
    if (_tabs.isEmpty && widget.visible) _open();
  }

  Future<void> _closeAll() async {
    final all = [..._tabs];
    _tabs.clear();
    for (final t in all) {
      // Cancel and close in parallel: awaiting the stream cancel before closing
      // the PTY can delay the close until the event loop turns.
      unawaited(t.sub?.cancel());
      await t.session?.close();
    }
    if (mounted) setState(() => _current = 0);
  }

  @override
  void dispose() {
    widget.shell.removeListener(_onShell);
    widget.pro.removeListener(_onPro);
    if (widget.shell.closeAllTerminals == _closeAll) {
      widget.shell.closeAllTerminals = null;
    }
    for (final t in _tabs) {
      t.sub?.cancel();
      t.session?.close();
    }
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.pro.isPro) {
      return SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.terminal,
                  size: 48,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  'Terminal is a Pro feature',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Run commands yourself in the Linux sandbox. '
                  'Build tools still work without it.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () =>
                      showPaywall(context, widget.pro, ProFeature.terminal),
                  child: const Text('Unlock Pro'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final tab = _tabs.isEmpty
        ? null
        : _tabs[_current.clamp(0, _tabs.length - 1)];
    return SafeArea(
      child: Column(
        children: [
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (var i = 0; i < _tabs.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 6,
                    ),
                    child: InputChip(
                      label: Text(_tabs[i].title),
                      selected: i == _current,
                      onPressed: () => setState(() => _current = i),
                      onDeleted: () => _closeTab(i),
                      deleteButtonTooltipMessage: 'Close',
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'New terminal',
                  onPressed: () => _open(),
                ),
              ],
            ),
          ),
          Expanded(
            child: tab == null
                // only animate while visible: an offstage spinner would keep the app scheduling frames
                ? Center(
                    child: widget.visible
                        ? const CircularProgressIndicator()
                        : const SizedBox.shrink(),
                  )
                : tab.error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(tab.error!),
                    ),
                  )
                : Stack(
                    children: [
                      TerminalView(
                        tab.terminal,
                        key: ObjectKey(tab),
                        autofocus: true,
                        hardwareKeyboardOnly: false,
                        textStyle: const TerminalStyle(fontSize: 13),
                      ),
                      if (tab.exited)
                        Positioned(
                          right: 12,
                          bottom: 12,
                          child: FilledButton.icon(
                            icon: const Icon(Icons.replay),
                            label: const Text('Restart'),
                            onPressed: () async {
                              await tab.sub?.cancel();
                              await tab.session?.close();
                              await _start(tab);
                            },
                          ),
                        ),
                    ],
                  ),
          ),
          if (tab != null) ExtraKeys(terminal: tab.terminal, ctrl: _ctrl),
        ],
      ),
    );
  }
}
