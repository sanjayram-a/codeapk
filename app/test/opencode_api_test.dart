import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:opencode_app/api/opencode_api.dart';

void main() {
  late HttpServer server;
  late Uri base;
  final requests = <({String method, String path, Map<String, String> query, Map<String, String> headers, String body})>[];
  late Future<void> Function(HttpRequest) handler;

  setUp(() async {
    requests.clear();
    server = await HttpServer.bind('127.0.0.1', 0);
    base = Uri.parse('http://127.0.0.1:${server.port}/');
    server.listen((req) async {
      final body = await utf8.decoder.bind(req).join();
      requests.add((
        method: req.method,
        path: req.uri.path,
        query: req.uri.queryParameters,
        headers: {for (final k in ['authorization', 'x-opencode-directory']) k: req.headers.value(k) ?? ''},
        body: body,
      ));
      await handler(req);
      await req.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  HttpOpencodeApi api() => HttpOpencodeApi(base: base, password: 'secret');

  void json(HttpRequest r, Object body, {int status = 200}) {
    r.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
  }

  Map<String, Object?> session(String id, String dir, int updated, {String title = 't'}) => {
        'id': id,
        'title': title,
        'directory': dir,
        'time': {'created': 1, 'updated': updated},
      };

  test('sends basic auth and the directory', () async {
    handler = (r) async => json(r, []);
    await api().listSessions(directories: ['/root']);
    expect(requests.single.headers['authorization'], 'Basic ${base64.encode(utf8.encode('opencode:secret'))}');
    expect(requests.single.query['directory'], '/root');
    expect(requests.single.headers['x-opencode-directory'], '/root');
  });

  test('merges sessions of several directories newest first and de-duplicates', () async {
    handler = (r) async {
      final dir = r.uri.queryParameters['directory'];
      json(r, dir == '/root'
          ? [session('a', '/root', 100), session('shared', '/root', 300)]
          : [session('b', '/root/p', 200), session('shared', '/root/p', 300)]);
    };
    final out = await api().listSessions(directories: ['/root', '/root/p']);
    expect(out.map((s) => s.id), ['shared', 'b', 'a']);
  });

  test('passes search and limit, and filters by title as a fallback', () async {
    handler = (r) async => json(r, [
          session('1', '/root', 3, title: 'Fix the parser'),
          session('2', '/root', 2, title: 'Write docs'),
        ]);
    final out = await api().listSessions(directories: ['/root'], search: 'parser', limit: 10);
    expect(requests.single.query['search'], 'parser');
    expect(requests.single.query['limit'], '10');
    expect(out.map((s) => s.id), ['1']);
  });

  test('limit applies to the merged result', () async {
    handler = (r) async => json(r, [for (var i = 0; i < 5; i++) session('${r.uri.queryParameters['directory']}$i', '/x', i)]);
    final out = await api().listSessions(directories: ['/a', '/b'], limit: 3);
    expect(out, hasLength(3));
  });

  test('a failing directory does not break the whole list', () async {
    handler = (r) async => r.uri.queryParameters['directory'] == '/bad'
        ? json(r, {'error': 'nope'}, status: 500)
        : json(r, [session('ok', '/good', 1)]);
    final out = await api().listSessions(directories: ['/bad', '/good']);
    expect(out.map((s) => s.id), ['ok']);
  });

  test('all directories failing throws', () async {
    handler = (r) async => json(r, {}, status: 500);
    expect(() => api().listSessions(directories: ['/a']), throwsA(isA<OpencodeApiException>()));
  });

  test('createSession posts the title in the right directory', () async {
    handler = (r) async => json(r, session('new', '/root/p', 5, title: 'Hello'));
    final s = await api().createSession(directory: '/root/p', title: 'Hello');
    expect(requests.single.method, 'POST');
    expect(requests.single.path, '/session');
    expect(requests.single.query['directory'], '/root/p');
    expect(jsonDecode(requests.single.body), {'title': 'Hello'});
    expect(s.id, 'new');
  });

  test('renameSession and deleteSession use the right method and path', () async {
    handler = (r) async => json(r, true);
    await api().renameSession('ses 1', 'New name', directory: '/root');
    await api().deleteSession('ses 1', directory: '/root');
    expect(requests[0].method, 'PATCH');
    expect(requests[0].path, '/session/ses%201');
    expect(jsonDecode(requests[0].body), {'title': 'New name'});
    expect(requests[1].method, 'DELETE');
    expect(requests[1].path, '/session/ses%201');
  });

  test('listProjects returns worktrees without the global root', () async {
    handler = (r) async => json(r, [
          {'id': 'global', 'worktree': '/'},
          {'id': 'p1', 'worktree': '/root/projects/app'},
        ]);
    expect(await api().listProjects(), ['/root/projects/app']);
  });

  test('401 and bad bodies become OpencodeApiException', () async {
    handler = (r) async => json(r, {}, status: 401);
    await expectLater(api().listProjects(), throwsA(isA<OpencodeApiException>().having((e) => e.statusCode, 'status', 401)));
    handler = (r) async => r.response.write('<html>nope</html>');
    await expectLater(api().listProjects(), throwsA(isA<OpencodeApiException>()));
  });

  test('connection refused becomes OpencodeApiException', () async {
    final dead = HttpOpencodeApi(base: Uri.parse('http://127.0.0.1:1/'), password: 'x');
    await expectLater(dead.listProjects(), throwsA(isA<OpencodeApiException>()));
  });

  group('chatUrl', () {
    test('deep-links to the session using the url-safe base64 directory', () {
      final s = SessionInfo(id: 'ses_1', title: '', directory: '/root/my projects/a', updated: DateTime(2026));
      final url = chatUrl(Uri.parse('http://127.0.0.1:4100/'), s);
      expect(url.origin, 'http://127.0.0.1:4100');
      final segments = url.pathSegments;
      expect(segments, hasLength(3));
      expect(segments[1], 'session');
      expect(segments[2], 'ses_1');
      expect(utf8.decode(base64Url.decode(base64Url.normalize(segments[0]))), '/root/my projects/a');
      expect(segments[0].contains('='), isFalse);
    });

    test('falls back to the root when the directory is unknown', () {
      final s = SessionInfo(id: 'x', title: '', directory: null, updated: DateTime(2026));
      expect(chatUrl(Uri.parse('http://127.0.0.1:4100/'), s).path, '/');
    });
  });

  group('groupSessions', () {
    final now = DateTime(2026, 11, 1, 15);
    SessionInfo at(String id, DateTime t) => SessionInfo(id: id, title: id, directory: '/root', updated: t);

    test('buckets by calendar day and drops empty buckets', () {
      final groups = groupSessions([
        at('today', DateTime(2026, 11, 1, 1)),
        at('yesterday', DateTime(2026, 10, 31, 23)),
        at('week', DateTime(2026, 10, 27)),
        at('old', DateTime(2026, 10, 1)),
      ], now);
      expect(groups.map((g) => g.label), ['Today', 'Yesterday', 'This week', 'Older']);
      expect(groupSessions([at('old', DateTime(2026, 1, 1))], now).map((g) => g.label), ['Older']);
      expect(groupSessions([], now), isEmpty);
    });

    test('empty title shows a placeholder', () {
      expect(SessionInfo(id: 'x', title: '  ', directory: null, updated: now).displayTitle, 'Untitled session');
    });

    test('fromJson tolerates missing fields', () {
      final s = SessionInfo.fromJson({'id': 'x'});
      expect(s.title, '');
      expect(s.directory, isNull);
    });
  });
}
