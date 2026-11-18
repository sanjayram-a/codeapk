import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opencode_app/chat/chat_session.dart';
import 'package:opencode_runtime/opencode_runtime.dart';

import 'fakes.dart';

ServerSnapshot running(int port, String pw) => ServerSnapshot(status: ServerStatus.running, port: port, password: pw);

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeRuntime rt;
  var foreground = true;
  late ChatSession session;

  void make() {
    session = ChatSession(rt, isForeground: () => foreground);
  }

  setUp(() {
    rt = FakeRuntime();
    foreground = true;
  });

  tearDown(() => session.dispose());

  test('attachesToRunningServer: no second start', () async {
    rt.current = running(4100, 'a');
    make();
    await settle();
    await session.ensureRunning();
    expect(rt.startCalls, 0);
    expect(session.base.toString(), 'http://127.0.0.1:4100/');
    expect(session.password, 'a');
  });

  test('startsWhenStopped', () async {
    make();
    await settle();
    await session.ensureRunning();
    expect(rt.startCalls, 1);
    expect(session.snapshot.isRunning, isTrue);
  });

  test('concurrent ensureRunning calls start once', () async {
    make();
    await settle();
    await Future.wait([session.ensureRunning(), session.ensureRunning(), session.ensureRunning()]);
    expect(rt.startCalls, 1);
  });

  test('restartsAfterIdleStop only in the foreground', () async {
    rt.current = running(4100, 'a');
    make();
    await settle();
    foreground = false;
    rt.emit(const ServerSnapshot(status: ServerStatus.stopped, stopReason: 'idle'));
    await settle();
    expect(rt.startCalls, 0);

    // coming back to the foreground brings the server back
    foreground = true;
    await session.onForeground();
    expect(rt.startCalls, 1);
  });

  test('restarts at once when stopped for idle while in the foreground', () async {
    rt.current = running(4100, 'a');
    make();
    await settle();
    rt.emit(const ServerSnapshot(status: ServerStatus.stopped, stopReason: 'idle'));
    await settle();
    await settle();
    expect(rt.startCalls, 1);
  });

  test('userStopIsNotRestarted', () async {
    rt.current = running(4100, 'a');
    make();
    await settle();
    rt.emit(const ServerSnapshot(status: ServerStatus.stopped, stopReason: 'user'));
    await settle();
    await session.onForeground();
    expect(rt.startCalls, 0);
    await session.ensureRunning(); // an explicit start still works
    expect(rt.startCalls, 1);
  });

  test('reloadsWhenPortOrPasswordChanges', () async {
    rt.current = running(4100, 'a');
    make();
    await settle();
    final g0 = session.generation;
    rt.emit(running(4100, 'a')); // identical: no reload
    await settle();
    expect(session.generation, g0);
    rt.emit(const ServerSnapshot(status: ServerStatus.restarting));
    await settle();
    expect(session.generation, g0);
    rt.emit(running(4207, 'b'));
    await settle();
    expect(session.generation, g0 + 1);
    expect(session.base.toString(), 'http://127.0.0.1:4207/');
    expect(session.password, 'b');
  });

  test('failedExposesLogTail and retry starts again', () async {
    make();
    await settle();
    rt.startError = PlatformException(code: 'server_start', message: 'not healthy', details: 'boom');
    await session.ensureRunning(); // must not throw
    rt.emit(const ServerSnapshot(status: ServerStatus.failed, error: 'not healthy', logTail: 'boom'));
    await settle();
    expect(session.snapshot.status, ServerStatus.failed);
    expect(session.snapshot.logTail, 'boom');
    expect(session.base, isNull);
    rt.startError = null;
    await session.retry();
    expect(rt.startCalls, 2);
    expect(session.snapshot.isRunning, isTrue);
  });
}
