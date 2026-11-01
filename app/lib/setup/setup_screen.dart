import 'package:flutter/material.dart';

import 'setup_controller.dart';

/// Shows install progress and the self-test result; the app moves on when the controller is ready.
class SetupScreen extends StatelessWidget {
  const SetupScreen({super.key, required this.controller});

  final SetupController controller;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) => ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 24),
                  Text(_title(controller.phase), style: text.headlineSmall),
                  const SizedBox(height: 16),
                  if (controller.phase == SetupPhase.installing || controller.phase == SetupPhase.selfTesting) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 12),
                    Text(
                      controller.phase == SetupPhase.installing
                          ? '${controller.entries} files unpacked — this only happens once.'
                          : 'Checking that Linux, Node, Python and OpenCode start…',
                    ),
                  ],
                  if (controller.phase == SetupPhase.failed) ...[
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: SelectableText(controller.error ?? 'Unknown error'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: controller.run, child: const Text('Try again')),
                  ],
                  if (controller.selfTest.isNotEmpty && controller.phase != SetupPhase.failed) ...[
                    const SizedBox(height: 16),
                    for (final e in controller.selfTest.entries)
                      ListTile(dense: true, title: Text(e.key), trailing: Text(e.value)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _title(SetupPhase p) => switch (p) {
        SetupPhase.idle || SetupPhase.installing => 'Setting up Linux…',
        SetupPhase.selfTesting => 'Testing the environment…',
        SetupPhase.ready => 'Ready',
        SetupPhase.failed => 'Setup did not finish',
      };
}
