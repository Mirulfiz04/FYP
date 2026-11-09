import 'admin_dashboard_models.dart' show ActivityStatus;
import 'detection_session.dart';
import 'emotion_reading.dart';
import 'session_liveness.dart';
import 'user_profile.dart';

export 'admin_dashboard_models.dart' show ActivityStatus, ActivityStatusLabel;

/// One row on the Monitor Sessions list: a session enriched with the user's
/// name, its dominant emotion and average heart rate, and a display status.
class MonitorSession {
  final DetectionSession session;
  final String userName;
  final String? email;
  final String? avatarUrl;
  final String initials;
  final ActivityStatus status;

  /// Effective duration: a real elapsed time for live sessions, the recorded
  /// span for ended ones, and the measured span (not the runaway "now − start")
  /// for abandoned `active` rows. Computed in [MonitorSessionsData.build].
  final Duration duration;
  final String emotion; // '—' when no readings
  final int avgBpm; // 0 when no valid heart-rate data

  const MonitorSession({
    required this.session,
    required this.userName,
    required this.email,
    required this.avatarUrl,
    required this.initials,
    required this.status,
    required this.duration,
    required this.emotion,
    required this.avgBpm,
  });

  String get sessionId => session.sessionId;
  DateTime get start => session.startTime.toLocal();

  bool matches(String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    return userName.toLowerCase().contains(q) ||
        (email ?? '').toLowerCase().contains(q) ||
        sessionId.toLowerCase().contains(q);
  }
}

/// Everything the Monitor Sessions screen renders. Pure data built from rows
/// the admin service already fetches — fully unit-testable, no Supabase.
class MonitorSessionsData {
  final List<MonitorSession> sessions; // newest first
  final int total;
  final int live;
  final int completed;
  final int flagged;
  final double totalDeltaPct;
  final double liveDeltaPct;
  final double completedDeltaPct;
  final int flaggedDelta; // count difference vs previous 7 days

  const MonitorSessionsData({
    required this.sessions,
    required this.total,
    required this.live,
    required this.completed,
    required this.flagged,
    required this.totalDeltaPct,
    required this.liveDeltaPct,
    required this.completedDeltaPct,
    required this.flaggedDelta,
  });

  static const empty = MonitorSessionsData(
    sessions: [],
    total: 0,
    live: 0,
    completed: 0,
    flagged: 0,
    totalDeltaPct: 0,
    liveDeltaPct: 0,
    completedDeltaPct: 0,
    flaggedDelta: 0,
  );

  static MonitorSessionsData build({
    required List<UserProfile> users,
    required List<DetectionSession> sessions,
    required List<EmotionReading> readings,
    DateTime? now,
  }) {
    final ref = now ?? DateTime.now();
    final weekAgo = ref.subtract(const Duration(days: 7));
    final twoWeeksAgo = ref.subtract(const Duration(days: 14));

    final byUser = {for (final u in users) u.id: u};
    final bySession = <String, List<EmotionReading>>{};
    for (final r in readings) {
      final sid = r.sessionId;
      if (sid != null) (bySession[sid] ??= []).add(r);
    }

    final rows = (List<DetectionSession>.from(sessions)
          ..sort((a, b) => b.startTime.compareTo(a.startTime)))
        .map((s) {
      final rs = bySession[s.sessionId] ?? const <EmotionReading>[];
      final counts = <String, int>{};
      for (final r in rs) {
        counts[r.emotion] = (counts[r.emotion] ?? 0) + 1;
      }
      final emotion = counts.isEmpty
          ? '—'
          : (counts.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value)))
              .first
              .key;
      final hr = rs.where((r) => r.hr > 0).map((r) => r.hr).toList();
      final avgBpm =
          hr.isEmpty ? 0 : (hr.reduce((a, b) => a + b) / hr.length).round();
      final lastReadingAt = lastReadingTime(rs);
      final profile = byUser[s.userId];
      return MonitorSession(
        session: s,
        userName: profile?.displayLabel ?? 'Unknown user',
        email: profile?.email,
        avatarUrl: profile?.avatarUrl,
        initials: profile?.initials ?? '?',
        status: activityStatusOf(s, lastReadingAt: lastReadingAt, now: ref),
        duration:
            effectiveSessionDuration(s, lastReadingAt: lastReadingAt, now: ref),
        emotion: emotion,
        avgBpm: avgBpm,
      );
    }).toList();

    int countCat(ActivityStatus st) =>
        rows.where((r) => r.status == st).length;

    // Deltas: sessions per category started this 7d vs the prior 7d.
    int started(ActivityStatus? st, DateTime start, DateTime end) {
      return rows.where((r) {
        if (st != null && r.status != st) return false;
        final t = r.start;
        return !t.isBefore(start) && t.isBefore(end);
      }).length;
    }

    double pct(int prev, int cur) {
      if (prev == 0) return cur == 0 ? 0 : 100;
      return ((cur - prev) / prev * 100).roundToDouble();
    }

    final totalThis = started(null, weekAgo, ref);
    final totalPrev = started(null, twoWeeksAgo, weekAgo);
    final liveThis = started(ActivityStatus.live, weekAgo, ref);
    final livePrev = started(ActivityStatus.live, twoWeeksAgo, weekAgo);
    final compThis = started(ActivityStatus.completed, weekAgo, ref);
    final compPrev = started(ActivityStatus.completed, twoWeeksAgo, weekAgo);
    final flagThis = started(ActivityStatus.flagged, weekAgo, ref);
    final flagPrev = started(ActivityStatus.flagged, twoWeeksAgo, weekAgo);

    return MonitorSessionsData(
      sessions: rows,
      total: rows.length,
      live: countCat(ActivityStatus.live),
      completed: countCat(ActivityStatus.completed),
      flagged: countCat(ActivityStatus.flagged),
      totalDeltaPct: pct(totalPrev, totalThis),
      liveDeltaPct: pct(livePrev, liveThis),
      completedDeltaPct: pct(compPrev, compThis),
      flaggedDelta: flagThis - flagPrev,
    );
  }
}

/// Maps a session to its display status (shared rule with the dashboard's
/// recent activity): genuinely-live → live, cancelled / failed-AI → flagged,
/// pending/processing AI → review, otherwise completed. An `active` row that is
/// no longer live (the app was closed without ending the session) is treated as
/// completed rather than "Live forever" — see [isSessionLive].
ActivityStatus activityStatusOf(
  DetectionSession s, {
  DateTime? lastReadingAt,
  DateTime? now,
}) {
  if (s.status == 'active') {
    return isSessionLive(s, lastReadingAt: lastReadingAt, now: now)
        ? ActivityStatus.live
        : ActivityStatus.completed;
  }
  if (s.status == 'cancelled') return ActivityStatus.flagged;
  if (s.aiSummaryStatus == 'failed') return ActivityStatus.flagged;
  if (s.aiSummaryStatus == 'pending' || s.aiSummaryStatus == 'processing') {
    return ActivityStatus.review;
  }
  return ActivityStatus.completed;
}
