import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'session.dart';

export 'session.dart';

class OpencodeApiException implements Exception {
  OpencodeApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'OpencodeApiException: $message';
}

/// The slice of OpenCode's HTTP API the app uses natively (history, search, new session). Chat itself is the
/// OpenCode web UI. Routes are listed in docs/opencode-api.md.
abstract class OpencodeApi {
  /// Sessions of all [directories] (each directory is its own OpenCode instance), newest first.
  Future<List<SessionInfo>> listSessions({required List<String> directories, String? search, int limit = 50});

  Future<SessionInfo> createSession({required String directory, String? title});
  Future<void> renameSession(String id, String title, {String? directory});
  Future<void> deleteSession(String id, {String? directory});

  /// Directories OpenCode knows as projects (git worktrees), without the global root.
  Future<List<String>> listProjects();
}

class HttpOpencodeApi implements OpencodeApi {
  HttpOpencodeApi({required this.base, required this.password, HttpClient? client})
      : _client = client ?? HttpClient()
          ..connectionTimeout = const Duration(seconds: 3);

  final Uri base;
  final String password;
  final HttpClient _client;

  String get _auth => 'Basic ${base64.encode(utf8.encode('opencode:$password'))}';

  @override
  Future<List<SessionInfo>> listSessions({required List<String> directories, String? search, int limit = 50}) async {
    final query = (search ?? '').trim();
    final byId = <String, SessionInfo>{};
    OpencodeApiException? lastError;
    var succeeded = 0;
    for (final dir in directories) {
      try {
        final body = await _request('GET', '/session', directory: dir, query: {
          if (query.isNotEmpty) 'search': query,
          'limit': '$limit',
        });
        succeeded++;
        for (final item in (body as List)) {
          final s = SessionInfo.fromJson((item as Map).cast<String, Object?>());
          final existing = byId[s.id];
          if (existing == null || s.updated.isAfter(existing.updated)) byId[s.id] = s;
        }
      } on OpencodeApiException catch (e) {
        lastError = e;
      } on TypeError {
        lastError = OpencodeApiException('unexpected session list');
      }
    }
    if (succeeded == 0 && lastError != null) throw lastError;
    var out = byId.values.toList()..sort((a, b) => b.updated.compareTo(a.updated));
    if (query.isNotEmpty) {
      // The server may ignore `search`; filtering again keeps results correct either way.
      final q = query.toLowerCase();
      out = out.where((s) => s.displayTitle.toLowerCase().contains(q)).toList();
    }
    return out.take(limit).toList();
  }

  @override
  Future<SessionInfo> createSession({required String directory, String? title}) async {
    final body = await _request('POST', '/session', directory: directory, json: {
      if (title != null && title.isNotEmpty) 'title': title,
    });
    try {
      return SessionInfo.fromJson((body as Map).cast<String, Object?>());
    } on TypeError {
      throw OpencodeApiException('unexpected create-session response');
    }
  }

  @override
  Future<void> renameSession(String id, String title, {String? directory}) async {
    await _request('PATCH', '/session/${Uri.encodeComponent(id)}', directory: directory, json: {'title': title});
  }

  @override
  Future<void> deleteSession(String id, {String? directory}) async {
    await _request('DELETE', '/session/${Uri.encodeComponent(id)}', directory: directory);
  }

  @override
  Future<List<String>> listProjects() async {
    final body = await _request('GET', '/project');
    try {
      return [
        for (final p in (body as List))
          if ((p as Map)['worktree'] is String && p['worktree'] != '/') p['worktree'] as String,
      ];
    } on TypeError {
      throw OpencodeApiException('unexpected project list');
    }
  }

  Future<Object?> _request(
    String method,
    String path, {
    String? directory,
    Map<String, String> query = const {},
    Object? json,
  }) async {
    final uri = base.replace(path: path, queryParameters: {
      ...query,
      'directory': ?directory,
    });
    try {
      final req = await _client.openUrl(method, uri).timeout(const Duration(seconds: 5));
      req.headers.set('authorization', _auth);
      if (directory != null) req.headers.set('x-opencode-directory', directory);
      if (json != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(json));
      }
      final res = await req.close().timeout(const Duration(seconds: 15));
      final text = await utf8.decodeStream(res);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw OpencodeApiException('HTTP ${res.statusCode}', statusCode: res.statusCode);
      }
      if (text.isEmpty) return null;
      try {
        return jsonDecode(text);
      } on FormatException {
        throw OpencodeApiException('server returned something that is not JSON');
      }
    } on OpencodeApiException {
      rethrow;
    } on SocketException catch (e) {
      throw OpencodeApiException('cannot reach the OpenCode server (${e.message})');
    } on TimeoutException {
      throw OpencodeApiException('the OpenCode server did not answer in time');
    } on HttpException catch (e) {
      throw OpencodeApiException(e.message);
    }
  }
}

/// URL that opens [s] in the OpenCode web UI. The web UI addresses a project by its directory, as URL-safe
/// base64 without padding, followed by `/session/<id>`.
Uri chatUrl(Uri base, SessionInfo s) {
  final dir = s.directory;
  if (dir == null || dir.isEmpty) return base.replace(path: '/', query: '');
  final encoded = base64Url.encode(utf8.encode(dir)).replaceAll('=', '');
  return base.replace(path: '/$encoded/session/${s.id}', query: '');
}
