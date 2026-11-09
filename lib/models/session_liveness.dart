import 'detection_session.dart';
import 'emotion_reading.dart';

/// Shared rule for telling a *genuinely live* session apart from one that was
/// abandoned — i.e. the row is still `active` only because the user closed /
/// killed the app without tapping "End Session", so the completion update never
/// ran. A live session saves a reading every ~5s (see [LiveSessionController]),
/// so a few minutes of silence is a decisive signal that monitoring has stopped.
///
/// Keeping this in one pure place means the admin list, the dashboard, the
/// user's history and the self-heal sweep all agree on what "Live" means.
const Duration kLiveSessionGrace = Duration(minutes: 3);

/// The newest reading timestamp in [readings], or null when there are none.
DateTime? lastReadingTime(Iterable<EmotionReading> readings) {
  DateTime? latest;
  for (final r in readings) {
    if (latest == null || r.createdAt.isAfter(latest)) latest = r.createdAt;
  }
  return latest;
}

/// True only when an `active` session is *still running*: it has shown activity
/// (a saved reading, or — before its first reading — just started) within
/// [kLiveSessionGrace]. A future-dated [lastReadingAt] (clock skew) also counts
/// as live. Non-`active` sessions are never live.
bool isSessionLive(
  DetectionSession s, {
  DateTime? lastReadingAt,
  DateTime? now,
}) {
  if (s.status != 'active') return false;
  final ref = now ?? DateTime.now();
  final last = lastReadingAt ?? s.startTime;
  return ref.difference(last) <= kLiveSessionGrace;
}

/// The duration to *display* for a session — never the runaway "now − start"
/// that an abandoned `active` row would otherwise produce:
///   • genuinely live   → elapsed since start (a real ticking session)
///   • ended / cancelled → its recorded span (`end_time − start_time`)
///   • abandoned active  → measured span up to its last reading (zero if it
///     never captured one).
Duration effectiveSessionDuration(
  DetectionSession s, {
  DateTime? lastReadingAt,
  DateTime? now,
}) {
  final ref = now ?? DateTime.now();
  final DateTime end;
  if (isSessionLive(s, lastReadingAt: lastReadingAt, now: ref)) {
    end = ref;
  } else {
    end = s.endTime ?? lastReadingAt ?? s.startTime;
  }
  final d = end.difference(s.startTime);
  return d.isNegative ? Duration.zero : d;
}

/// One abandoned session the self-heal should close, with the end time to stamp.
class AbandonedSessionClose {
  final String sessionId;
  final DateTime endTime;
  const AbandonedSessionClose(this.sessionId, this.endTime);
}

/// The `active` sessions in [sessions] that are no longer live and should be
/// stamped ended, each paired with the end time to record (its last reading, or
/// its start when it never captured one). Pure — the caller issues the writes.
List<AbandonedSessionClose> abandonedActiveSessions(
  List<DetectionSession> sessions,
  Map<String, DateTime?> lastReadingBySession, {
  DateTime? now,
}) {
  final ref = now ?? DateTime.now();
  final out = <AbandonedSessionClose>[];
  for (final s in sessions) {
    if (s.status != 'active') continue;
    final last = lastReadingBySession[s.sessionId];
    if (isSessionLive(s, lastReadingAt: last, now: ref)) continue;
    out.add(AbandonedSessionClose(s.sessionId, last ?? s.startTime));
  }
  return out;
}
