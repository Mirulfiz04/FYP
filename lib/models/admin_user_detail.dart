import 'detection_session.dart';
import 'emotion_reading.dart';

/// Aggregated, read-only stats for one user's detail page. Pure data built from
/// rows the admin service already fetches — unit-testable, no Supabase.
class UserDetailStats {
  final int totalSessions;
  final int completedSessions;
  final int avgBpm; // 0 when no valid heart-rate data
  final String dominantEmotion; // '—' when no readings
  final DateTime? lastActive; // most recent session start (login proxy)
  final List<DetectionSession> recentSessions; // newest first, up to 5

  const UserDetailStats({
    required this.totalSessions,
    required this.completedSessions,
    required this.avgBpm,
    required this.dominantEmotion,
    required this.lastActive,
    required this.recentSessions,
  });

  bool get hasData => totalSessions > 0;

  static const empty = UserDetailStats(
    totalSessions: 0,
    completedSessions: 0,
    avgBpm: 0,
    dominantEmotion: '—',
    lastActive: null,
    recentSessions: [],
  );

  static UserDetailStats build({
    required List<DetectionSession> sessions,
    required List<EmotionReading> readings,
  }) {
    if (sessions.isEmpty && readings.isEmpty) return empty;

    final completed = sessions.where((s) => s.status == 'completed').length;

    final hr = readings.where((r) => r.hr > 0).map((r) => r.hr).toList();
    final avgBpm =
        hr.isEmpty ? 0 : (hr.reduce((a, b) => a + b) / hr.length).round();

    final counts = <String, int>{};
    for (final r in readings) {
      counts[r.emotion] = (counts[r.emotion] ?? 0) + 1;
    }
    final dominant = counts.isEmpty
        ? '—'
        : (counts.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value)))
            .first
            .key;

    final sorted = List<DetectionSession>.from(sessions)
      ..sort((a, b) => b.startTime.compareTo(a.startTime));
    final lastActive = sorted.isEmpty ? null : sorted.first.startTime.toLocal();

    return UserDetailStats(
      totalSessions: sessions.length,
      completedSessions: completed,
      avgBpm: avgBpm,
      dominantEmotion: dominant,
      lastActive: lastActive,
      recentSessions: sorted.take(5).toList(),
    );
  }
}
