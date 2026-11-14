import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opencode_app/app_deps.dart';
import 'package:opencode_app/chat/chat_session.dart';
import 'package:opencode_app/environment/command_task_page.dart';
import 'package:opencode_app/environment/environment_page.dart';
import 'package:opencode_app/files/file_editor_page.dart';
import 'package:opencode_app/pro/billing_gateway.dart';
import 'package:opencode_app/pro/pro_controller.dart';
import 'package:opencode_app/settings/settings_store.dart';
import 'package:opencode_app/settings/settings_tab.dart';
import 'package:opencode_app/shell/shell_controller.dart';
import 'package:opencode_runtime/opencode_runtime.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

void main() {
  late FakeRuntime rt;
  late ShellController shell;
  late SettingsStore settings;
  late ProController pro;
  ChatSession? chat;
  var resetDone = 0;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    rt = FakeRuntime();
    shell = ShellController();
    settings = SettingsStore(await SharedPreferences.getInstance());
    pro = ProController(FakeBillingGateway(), settings);
    await pro.initialize();
    chat = null;
    resetDone = 0;
  });

  tearDown(() {
    chat?.dispose();
    pro.dispose();
  });

  Future<void> pumpSettings(WidgetTester tester, {bool isPro = true}) async {
    // created here, not in setUp, so its stream subscription lives in the test's own zone
    final session = chat = ChatSession(rt, isForeground: () => true);
    final gateway = FakeBillingGateway();
    if (isPro) {
      gateway.purchases = const [
        BillingPurchase(
          productId: proProductId,
          purchaseToken: 'settings-tok',
          status: BillingPurchaseStatus.purchased,
          pendingCompletePurchase: false,
        ),
      ];
    }
    final pro = ProController(gateway, settings);
    await pro.initialize();
    addTearDown(pro.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsTab(
            deps: AppDeps(runtime: rt, settings: settings, pro: pro),
            chat: session,
            shell: shell,
            onResetDone: () => resetDone++,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('idle timeout choice persists and is sent to the runtime', (
    tester,
  ) async {
    await pumpSettings(tester);
    await tester.ensureVisible(find.byType(DropdownButton<int>));
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('30 min').last);
    await tester.pumpAndSettle();
    expect(settings.idleMinutes, 30);
    expect(rt.idleMinutes, [30]);
  });

  testWidgets('server section reflects the state and offers start/stop', (
    tester,
  ) async {
    await pumpSettings(tester);
    expect(find.text('Server stopped'), findsOneWidget);
    await tester.ensureVisible(find.text('Start'));
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(rt.startCalls, 1);
    expect(find.text('Server running'), findsOneWidget);
    await tester.ensureVisible(find.text('Stop'));
    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    expect(rt.log, contains('stopServer'));
  });

  testWidgets('server log opens in a sheet', (tester) async {
    rt.logText = 'line one\nline two';
    await pumpSettings(tester);
    await tester.ensureVisible(find.text('Server log'));
    await tester.tap(find.text('Server log'));
    await tester.pumpAndSettle();
    expect(find.textContaining('line two'), findsOneWidget);
  });

  testWidgets('free settings shows the plan card and opens the paywall', (
    tester,
  ) async {
    await pumpSettings(tester, isPro: false);
    expect(find.text('Free plan'), findsOneWidget);
    expect(find.text('Founder price'), findsOneWidget);
    await tester.tap(find.text('Unlock lifetime Pro'));
    await tester.pumpAndSettle();
    expect(find.text('Get OpenCode Pocket Pro'), findsOneWidget);
  });

  testWidgets('pro settings shows the lifetime plan', (tester) async {
    await pumpSettings(tester);
    expect(find.text('Pro — lifetime'), findsOneWidget);
    expect(find.text('Unlock lifetime Pro'), findsNothing);
  });

  testWidgets('free cannot choose an idle timeout above five minutes', (
    tester,
  ) async {
    await pumpSettings(tester, isPro: false);
    await tester.ensureVisible(find.byType(DropdownButton<int>));
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('30 min').last);
    await tester.pumpAndSettle();
    expect(find.text('Get OpenCode Pocket Pro'), findsOneWidget);
    expect(settings.idleMinutes, 15);
    expect(rt.idleMinutes, isEmpty);
  });

  testWidgets('free can still choose five minutes', (tester) async {
    await pumpSettings(tester, isPro: false);
    await tester.ensureVisible(find.byType(DropdownButton<int>));
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5 min (Free)').last);
    await tester.pumpAndSettle();
    expect(find.text('Get OpenCode Pocket Pro'), findsNothing);
    expect(settings.idleMinutes, 5);
    expect(rt.idleMinutes, [5]);
  });

  group('environment page', () {
    Future<void> pumpEnv(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => EnvironmentPage(
                        runtime: rt,
                        shell: shell,
                        onResetDone: () => resetDone++,
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
    }

    testWidgets('shows versions and sizes', (tester) async {
      await pumpEnv(tester);
      expect(find.text('v24.0.0'), findsOneWidget);
      expect(find.text('1.19.4'), findsOneWidget);
      expect(find.text('400 MB'), findsOneWidget);
      expect(find.text('2.0 MB'), findsOneWidget);
    });

    testWidgets('reset asks for confirmation and does nothing on cancel', (
      tester,
    ) async {
      await pumpEnv(tester);
      await tester.tap(find.text('Reset environment'));
      await tester.pumpAndSettle();
      expect(find.textContaining('are kept'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(rt.log, isNot(contains('resetEnvironment')));
      expect(resetDone, 0);
    });

    testWidgets(
      'confirmed reset stops the server first, then resets, then restarts setup',
      (tester) async {
        var terminalsClosed = false;
        shell.closeAllTerminals = () async {
          terminalsClosed = true;
          rt.log.add('closeTerminals');
        };
        await pumpEnv(tester);
        await tester.tap(find.text('Reset environment'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Reset'));
        await tester.pumpAndSettle();
        expect(terminalsClosed, isTrue);
        expect(
          rt.log.where(
            (l) => [
              'closeTerminals',
              'stopServer',
              'resetEnvironment',
            ].contains(l),
          ),
          ['closeTerminals', 'stopServer', 'resetEnvironment'],
        );
        expect(resetDone, 1);
        expect(
          find.byType(EnvironmentPage),
          findsNothing,
        ); // popped so the setup screen can show
      },
    );

    testWidgets('install build tools opens the read-only task sheet', (
      tester,
    ) async {
      await pumpEnv(tester);
      await tester.tap(find.text('Install build tools'));
      await tester.pumpAndSettle();
      expect(find.byType(CommandTaskPage), findsOneWidget);
      expect(rt.log, contains('openTerminal ${buildToolsCommand.join(' ')}'));
      expect(shell.tab, isNot(ShellController.terminalTab));
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('extra packages restore in the read-only task sheet', (
      tester,
    ) async {
      rt.env = const EnvironmentInfo(
        rootfsBytes: 1024,
        homeBytes: 1024,
        rootfsVersion: 'x',
        extraPackages: ['build-base', 'vim'],
      );
      await pumpEnv(tester);
      expect(find.text('Restore 2 extra package(s)'), findsOneWidget);
      await tester.tap(find.text('Restore 2 extra package(s)'));
      await tester.pumpAndSettle();
      expect(find.byType(CommandTaskPage), findsOneWidget);
      expect(
        rt.log,
        contains('openTerminal ${restoreExtrasCommand.join(' ')}'),
      );
    });
  });

  group('config editor', () {
    test(
      'validateConfigJson accepts an object and rejects everything else',
      () {
        expect(validateConfigJson('{"model": "x"}'), isNull);
        expect(validateConfigJson('{}'), isNull);
        expect(validateConfigJson('{"a":'), startsWith('Invalid JSON'));
        expect(validateConfigJson('[1]'), contains('object'));
        expect(validateConfigJson(''), isNotNull);
      },
    );

    testWidgets('invalid JSON blocks Save, valid JSON saves', (tester) async {
      rt.texts[opencodeConfigPath] = '{}';
      await tester.pumpWidget(
        MaterialApp(
          home: FileEditorPage(
            runtime: rt,
            path: opencodeConfigPath,
            pro: pro,
            validate: validateConfigJson,
          ),
        ),
      );
      await tester.pumpAndSettle();
      TextButton button() =>
          tester.widget<TextButton>(find.widgetWithText(TextButton, 'Save'));
      expect(button().onPressed, isNull); // unchanged

      await tester.enterText(find.byType(TextField), '{"model": ');
      await tester.pump();
      expect(find.textContaining('Invalid JSON'), findsOneWidget);
      expect(button().onPressed, isNull);

      await tester.enterText(
        find.byType(TextField),
        '{"model": "anthropic/claude"}',
      );
      await tester.pump();
      expect(button().onPressed, isNotNull);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(rt.texts[opencodeConfigPath], '{"model": "anthropic/claude"}');
    });

    testWidgets(
      'a binary or oversized file shows a message instead of an editor',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: FileEditorPage(
              runtime: _FailingRead(),
              path: '/root/big.bin',
              pro: pro,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('cannot be edited here'), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
      },
    );
  });
}

/// Throws like the native side does for a binary or oversized file.
class _FailingRead extends FakeRuntime {
  @override
  Future<String> readText(String path) async =>
      throw PlatformException(code: 'invalid', message: 'binary file');
}
