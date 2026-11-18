/// One OpenCode session, as shown in the history list.
class SessionInfo {
  const SessionInfo({required this.id, required this.title, required this.directory, required this.updated});

  final String id;

  /// Raw title; empty for a session that has not been named yet. Use [displayTitle] in the UI.
  final String title;
  final String? directory;
  final DateTime updated;

  String get displayTitle => title.trim().isEmpty ? 'Untitled session' : title.trim();

  factory SessionInfo.fromJson(Map<String, Object?> json) {
    final time = json['time'];
    final ms = time is Map ? (time['updated'] ?? time['created']) : null;
    return SessionInfo(
      id: json['id'] as String,
      title: (json['title'] as String?) ?? '',
      directory: json['directory'] as String?,
      updated: DateTime.fromMillisecondsSinceEpoch(ms is num ? ms.toInt() : 0),
    );
  }
}

class SessionGroup {
  const SessionGroup(this.label, this.sessions);

  final String label;
  final List<SessionInfo> sessions;
}

/// Buckets sessions (already sorted newest first) into Today / Yesterday / This week / Older.
/// Empty buckets are left out.
List<SessionGroup> groupSessions(List<SessionInfo> sessions, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final weekStart = today.subtract(const Duration(days: 6));
  final buckets = <String, List<SessionInfo>>{
    'Today': [],
    'Yesterday': [],
    'This week': [],
    'Older': [],
  };
  for (final s in sessions) {
    final day = DateTime(s.updated.year, s.updated.month, s.updated.day);
    final key = !day.isBefore(today)
        ? 'Today'
        : !day.isBefore(yesterday)
            ? 'Yesterday'
            : !day.isBefore(weekStart)
                ? 'This week'
                : 'Older';
    buckets[key]!.add(s);
  }
  return [
    for (final e in buckets.entries)
      if (e.value.isNotEmpty) SessionGroup(e.key, e.value),
  ];
}
