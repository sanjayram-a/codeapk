import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opencode_app/environment/command_task_page.dart';
import 'package:opencode_app/environment/environment_page.dart';

import 'fakes.dart';

void main() {
  testWidgets('runs the command, shows output, and has no input', (
    tester,
  ) async {
    final rt = FakeRuntime();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CommandTaskPage(
                      runtime: rt,
                      title: 'Installing build tools',
                      command: buildToolsCommand,
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Installing build tools'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(rt.log, contains('openTerminal ${buildToolsCommand.join(' ')}'));

    rt.terminals.single.controller.add(utf8.encoder.convert('working\n'));
    // The fake terminal's broadcast stream delivers on a later microtask, so
    // the first pump can draw the pre-event frame; a second pump shows it.
    await tester.pump();
    await tester.pump();
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      contains('working'),
    );

    await rt.terminals.single.controller.close();
    await tester.pumpAndSettle();
    expect(find.text('Done'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(CommandTaskPage), findsNothing);
  });
}
