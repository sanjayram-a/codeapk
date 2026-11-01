import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opencode_app/setup/setup_controller.dart';

import 'fakes.dart';

void main() {
  late FakeRuntime rt;
  late SetupController c;
  late List<SetupPhase> phases;

  setUp(() {
    rt = FakeRuntime();
    c = SetupController(rt);
    phases = [];
    c.addListener(() {
      if (phases.isEmpty || phases.last != c.phase) phases.add(c.phase);
    });
  });

  test('success path: installing, selfTesting, ready', () async {
    await c.run();
    expect(phases, [SetupPhase.installing, SetupPhase.selfTesting, SetupPhase.ready]);
    expect(c.entries, 200);
    expect(c.selfTest['opencode'], '1.19.4');
    expect(c.error, isNull);
  });

  test('an install error fails with the message, and run() retries', () async {
    rt.installError = PlatformException(code: 'IOException', message: 'disk full');
    await c.run();
    expect(c.phase, SetupPhase.failed);
    expect(c.error, 'disk full');
    expect(rt.log, isNot(contains('selfTest')));
    rt.installError = null;
    await c.run();
    expect(c.phase, SetupPhase.ready);
    expect(c.error, isNull);
  });

  test('a self-test that misses a value fails', () async {
    rt.selfTestResult = {'arch': 'aarch64', 'node': 'v24', 'python': ''};
    await c.run();
    expect(c.phase, SetupPhase.failed);
    expect(c.error, contains('python'));
    expect(c.error, contains('opencode'));
  });

  test('run() while already running is ignored', () async {
    final first = c.run();
    await c.run();
    await first;
    expect(rt.installCalls, 1);
  });
}
