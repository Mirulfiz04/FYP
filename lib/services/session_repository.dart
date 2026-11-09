import 'dart:async';

import '../models/ai_insight.dart';
import '../models/emotion_reading.dart';
import '../models/session_liveness.dart';
import '../models/session_summary.dart';
import 'supabase_service.dart';

/// Source of session-history records. Keeps all data access out of the UI and
/// view model, so the backing store (Supabase, sample data, a cache) can be
/// swapped without touching the rest.
abstract class SessionRepository {
  Future<List<SessionSummary>> loadSessions();
}

/// Loads real sessions from Supabase: one query for sessions, one for the
/// user's readings, grouped client-side into per-session [SessionSummary]s.
class SupabaseSessionRepository implements SessionRepository {
  final SupabaseService _svc;
  SupabaseSessionRepository([SupabaseService? svc])
      : _svc = svc ?? SupabaseService();

  @override
  Future<List<SessionSummary>> loadSessions() async {
    final uid = _svc.currentUserId;
    if (uid == null) return [];

    final sessions = await _svc.fetchSessions(limit: 200);
    if (sessions.isEmpty) return [];

    final readings = await _svc.fetchReadingsForUser(uid, limit: 5000);
    final bySession = <String, List<EmotionReading>>{};
    for (final r in readings) {
      final sid = r.sessionId;
      if (sid != null) (bySession[sid] ??= []).add(r);
    }

    // Self-heal: close any of this user's own sessions left "active" because the
    // app was closed without ending them. Fire-and-forget so the list returns
    // immediately; the display layer already shows the correct state meanwhile.
    final lastReadingBySession = {
      for (final e in bySession.entries) e.key: lastReadingTime(e.value),
    };
    unawaited(_svc.closeAbandonedSessions(sessions, lastReadingBySession));

    return sessions
        .map((s) =>
            SessionSummary.fromSession(s, bySession[s.sessionId] ?? const []))
        .toList();
  }
}

/// Deterministic in-memory sessions for demos / tests / offline preview, behind
/// the same interface so it can replace the Supabase repository transparently.
class SampleSessionRepository implements SessionRepository {
  final DateTime _now;
  SampleSessionRepository({DateTime? now}) : _now = now ?? DateTime.now();

  @override
  Future<List<SessionSummary>> loadSessions() async {
    SessionSummary make({
      required String id,
      required DateTime start,
      required int minutes,
      required int seconds,
      required String emotion,
      required double confidence,
      required int avg,
      required int minBpm,
      required int maxBpm,
      AiSummaryStatus ai = AiSummaryStatus.completed,
    }) {
      return SessionSummary(
        sessionId: id,
        userId: 'sample-user',
        startTime: start,
        endTime: start.add(Duration(minutes: minutes, seconds: seconds)),
        duration: Duration(minutes: minutes, seconds: seconds),
        dominantEmotion: emotion,
        emotionConfidence: confidence,
        averageBpm: avg,
        minimumBpm: minBpm,
        maximumBpm: maxBpm,
        finalState: SessionSummary.deriveFinalState(emotion, avg),
        aiSummaryStatus: ai,
        aiSummary: ai == AiSummaryStatus.completed
            ? const AiInsight(
                emotionalSummary: 'A balanced, positive session overall.',
                stressLevel: 'Low',
                trendAnalysis: 'Heart rate stayed within a calm range.',
                recommendations: ['Keep up your good routine.'],
              )
            : null,
        status: 'completed',
        createdAt: start,
      );
    }

    final today = DateTime(_now.year, _now.month, _now.day, 9, 30);
    return [
      make(id: 's1', start: today, minutes: 5, seconds: 30, emotion: 'Happy', confidence: 88, avg: 78, minBpm: 70, maxBpm: 92),
      make(id: 's2', start: today.subtract(const Duration(hours: 2, minutes: 15)), minutes: 4, seconds: 45, emotion: 'Neutral', confidence: 81, avg: 74, minBpm: 66, maxBpm: 85, ai: AiSummaryStatus.notRequested),
      make(id: 's3', start: today.subtract(const Duration(days: 1, hours: 3)), minutes: 6, seconds: 10, emotion: 'Angry', confidence: 79, avg: 96, minBpm: 80, maxBpm: 110),
      make(id: 's4', start: today.subtract(const Duration(days: 1, hours: 9)), minutes: 4, seconds: 20, emotion: 'Sad', confidence: 76, avg: 82, minBpm: 72, maxBpm: 95, ai: AiSummaryStatus.processing),
      make(id: 's5', start: today.subtract(const Duration(days: 2, hours: 1)), minutes: 5, seconds: 55, emotion: 'Happy', confidence: 84, avg: 88, minBpm: 78, maxBpm: 101),
    ];
  }
}
