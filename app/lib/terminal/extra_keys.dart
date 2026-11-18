import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import 'ctrl_keys.dart';

/// Keys a phone keyboard lacks: Esc, Tab, a sticky Ctrl, arrows, Home/End, Page up/down and a few symbols.
/// Keys go through the terminal's own key handling, so application modes (vim, less) are respected.
class ExtraKeys extends StatelessWidget {
  const ExtraKeys({super.key, required this.terminal, required this.ctrl});

  final Terminal terminal;
  final CtrlState ctrl;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: SizedBox(
        height: 44,
        child: ListenableBuilder(
          listenable: ctrl,
          builder: (context, _) => ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            children: [
              _key('Esc', () => terminal.keyInput(TerminalKey.escape)),
              _key('Tab', () => terminal.keyInput(TerminalKey.tab)),
              _key('Ctrl', ctrl.toggle, active: ctrl.armed),
              _key('↑', () => _arrow(TerminalKey.arrowUp)),
              _key('↓', () => _arrow(TerminalKey.arrowDown)),
              _key('←', () => _arrow(TerminalKey.arrowLeft)),
              _key('→', () => _arrow(TerminalKey.arrowRight)),
              _key('Home', () => terminal.keyInput(TerminalKey.home)),
              _key('End', () => terminal.keyInput(TerminalKey.end)),
              _key('PgUp', () => terminal.keyInput(TerminalKey.pageUp)),
              _key('PgDn', () => terminal.keyInput(TerminalKey.pageDown)),
              for (final s in const ['|', '/', '-', '~', '_', '"', "'"]) _key(s, () => terminal.textInput(s)),
            ],
          ),
        ),
      ),
    );
  }

  void _arrow(TerminalKey key) {
    final withCtrl = ctrl.armed;
    ctrl.disarm();
    terminal.keyInput(key, ctrl: withCtrl);
  }

  Widget _key(String label, VoidCallback onTap, {bool active = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
        child: FilledButton.tonal(
          style: FilledButton.styleFrom(
            minimumSize: const Size(44, 34),
            padding: const EdgeInsets.symmetric(horizontal: 10),
).copyWith(
            backgroundColor: active ? WidgetStatePropertyAll(Colors.orange.shade300) : null,
          ),
          onPressed: onTap,
          child: Text(label),
        ),
      );
}
