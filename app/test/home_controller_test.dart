import 'package:flutter_test/flutter_test.dart';
import 'package:opencode_app/api/opencode_api.dart';
import 'package:opencode_app/home/home_controller.dart';

import 'fakes.dart';

void main() {
  final now = DateTime(2026, 11, 1, 12);
  SessionInfo s(String id, DateTime t, {String title = 'x'}) =>
      SessionInfo(id: id, title: title, directory: '/root', updated: t);

  HomeController make(FakeOpencodeApi? api, {List<String> folders = const []}) => HomeController(
        api: () => api,
        extraDirectories: () async => folders,
        debounce: const Duration(milliseconds: 20),
        now: () => now,
      );

  test('groups sessions by day', () async {
    final api = FakeOpencodeApi()
      ..sessions = [s('a', DateTime(2026, 11, 1, 9)), s('b', DateTime(2026, 10, 31)), s('c', DateTime(2026, 9, 1))];
    final c = make(api);
    await c.refresh();
    expect(c.groups.map((g) => g.label), ['Today', 'Yesterday', 'Older']);
    expect(c.loading, isFalse);
    expect(c.error, isNull);
  });

  test('queries /root, the known projects and the project folders', () async {
    final api = FakeOpencodeApi()..projects = ['/root/projects/git-app'];
    final c = make(api, folders: ['/root/projects/a', '/root/projects/git-app']);
    await c.refresh();
    expect(api.calls.single.dirs, ['/root', '/root/projects/git-app', '/root/projects/a']);
  });

  test('a failing project lookup still lists /root sessions', () async {
    final api = FakeOpencodeApi();
    final c = HomeController(
      api: () => api,
      extraDirectories: () async => throw Exception('files unavailable'),
      debounce: const Duration(milliseconds: 20),
      now: () => now,
    );
    await c.refresh();
    expect(api.calls.single.dirs, ['/root']);
    expect(c.error, isNull);
  });

  test('typing triggers one search after the debounce, not one per keystroke', () async {
    final api = FakeOpencodeApi();
    final c = make(api);
    c.setQuery('p');
    c.setQuery('pa');
    c.setQuery('par');
    expect(api.calls, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(api.calls, hasLength(1));
    expect(api.calls.single.search, 'par');
    expect(c.query, 'par');
  });

  test('a failed refresh keeps the previous list and reports the error', () async {
    final api = FakeOpencodeApi()..sessions = [s('a', DateTime(2026, 11, 1))];
    final c = make(api);
    await c.refresh();
    api.error = OpencodeApiException('cannot reach the server');
    await c.refresh();
    expect(c.groups.single.sessions.single.id, 'a');
    expect(c.error, 'cannot reach the server');
    api.error = null;
    await c.refresh();
    expect(c.error, isNull);
  });

  test('with the server not running the list is empty and there is no error', () async {
    final c = make(null);
    await c.refresh();
    expect(c.groups, isEmpty);
    expect(c.error, isNull);
    expect(c.loading, isFalse);
  });

  test('an older response never overwrites a newer one', () async {
    final api = FakeOpencodeApi();
    final c = make(api);
    final first = c.refresh();
    api.sessions = [s('newer', DateTime(2026, 11, 1))];
    await c.refresh();
    await first;
    expect(c.groups.single.sessions.single.id, 'newer');
  });

  test('delete and rename go to the api and refresh', () async {
    final api = FakeOpencodeApi()..sessions = [s('a', DateTime(2026, 11, 1))];
    final c = make(api);
    await c.refresh();
    await c.delete(api.sessions.first);
    await c.rename(api.sessions.first, 'New');
    expect(api.deleted, ['a']);
    expect(api.renamed, ['a=New']);
    expect(api.calls.length, 3); // initial + one refresh after each change
  });
}
