import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opencode_app/api/opencode_api.dart';
import 'package:opencode_app/app.dart';
import 'package:opencode_app/app_deps.dart';
import 'package:opencode_app/onboarding/onboarding_screen.dart';
import 'package:opencode_app/settings/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

void main() {
  late FakeRuntime rt;
  late FakeOpencodeApi api;

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  Future<AppDeps> deps({bool consented = false}) async {
    SharedPreferences.setMockInitialValues({if (consented) 'consent_accepted': true});
    rt = FakeRuntime();
    api = FakeOpencodeApi();
    return AppDeps(
      runtime: rt,
      settings: SettingsStore(await SharedPreferences.getInstance()),
      apiFactory: (_, _) => api,
    );
  }

  testWidgets('fresh install shows the disclosure and installs nothing before consent', (tester) async {
    phone(tester);
    await tester.pumpWidget(OpencodeApp(deps: await deps()));
    await tester.pump();
    expect(find.text(OnboardingScreen.title), findsOneWidget);
    expect(find.textContaining('The AI can run commands there'), findsOneWidget);
    expect(rt.installCalls, 0);
    expect(rt.startCalls, 0);
  });

  testWidgets('consent leads through setup to the home page', (tester) async {
    phone(tester);
    await tester.pumpWidget(OpencodeApp(deps: await deps()));
    await tester.tap(find.text('I understand, continue'));
    await tester.pumpAndSettle();
    expect(rt.installCalls, 1);
    expect(rt.log, containsAllInOrder(['install', 'selfTest', 'startServer']));
    expect(find.text('No sessions yet'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    for (final label in ['Home', 'Files', 'Terminal', 'Settings']) {
      expect(find.text(label), findsWidgets);
    }
  });

  testWidgets('a returning user skips onboarding', (tester) async {
    phone(tester);
    await tester.pumpWidget(OpencodeApp(deps: await deps(consented: true)));
    await tester.pumpAndSettle();
    expect(find.text(OnboardingScreen.title), findsNothing);
    expect(rt.installCalls, 1);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('deniedNotificationsDoNotBlock', (tester) async {
    phone(tester);
    final d = await deps();
    rt.notificationsGranted = false;
    await tester.pumpWidget(OpencodeApp(deps: d));
    await tester.ensureVisible(find.text('Allow notifications')); // the content scrolls on a small phone
    await tester.tap(find.text('Allow notifications'));
    await tester.pumpAndSettle();
    expect(find.textContaining('OpenCode still works'), findsOneWidget);
    await tester.tap(find.text('I understand, continue'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('a failed setup shows the error and can be retried', (tester) async {
    phone(tester);
    final d = await deps(consented: true);
    rt.selfTestError = StateError('proot crashed');
    await tester.pumpWidget(OpencodeApp(deps: d));
    await tester.pumpAndSettle();
    expect(find.text('Setup did not finish'), findsOneWidget);
    expect(find.textContaining('proot crashed'), findsOneWidget);
    rt.selfTestError = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('home lists sessions from the api grouped by day and filters on search', (tester) async {
    phone(tester);
    final d = await deps(consented: true);
    final now = DateTime.now();
    api.sessions = [
      SessionInfo(id: '1', title: 'Fix login bug', directory: '/root', updated: now),
      SessionInfo(id: '2', title: 'Add dark mode', directory: '/root', updated: now.subtract(const Duration(days: 30))),
    ];
    await tester.pumpWidget(OpencodeApp(deps: d));
    await tester.pumpAndSettle();
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Older'), findsOneWidget);
    expect(find.text('Fix login bug'), findsOneWidget);

    await tester.enterText(find.byType(SearchBar), 'dark');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(api.calls.last.search, 'dark');
  });
}
