import 'package:intl/intl.dart';

import 'ai_insight.dart';
import 'detection_session.dart';
import 'emotion_reading.dart';
import 'session_liveness.dart';

/// Lifecycle of a session's AI insight.
enum AiSummaryStatus {
  notRequested,
  pending,
  processing,
  completed,
  failed;

  /// Maps the raw `detection_sessions.ai_summary_status` string (+ whether a
  /// summary is actually stored) onto a status.
  static AiSummaryStatus fromRaw(String? raw, {required bool hasSummary}) {
    switch (raw) {
      case 'completed':
        return AiSummaryStatus.completed;
      case 'processing':
        return AiSummaryStatus.processing;
      case 'failed':
        return AiSummaryStatus.failed;
      case 'skipped':
        // Abandoned session closed by the self-heal: no AI was generated.
        return AiSummaryStatus.notRequested;
      case 'pending':
        return hasSummary ? AiSummaryStatus.completed : AiSummaryStatus.pending;
      default:
        return hasSummary ? AiSummaryStatus.completed : AiSummaryStatus.notRequested;
    }
  }

  bool get isAvailable => this == AiSummaryStatus.completed;

  /// The label shown on a history card.
  String get label => switch (this) {
        AiSummaryStatus.completed => 'AI Insight available',
        AiSummaryStatus.processing => 'Generating AI insight...',
        _ => 'AI insight not generated',
      };
}

/// A per-session record for the History screen: a [DetectionSession] plus
/// aggregates computed from its readings. Pure Dart (no Flutter) so the
/// filtering/search logic is unit-testable.
class SessionSummary {
  final String sessionId;
  final String userId;
  final DateTime startTime;
  final DateTime? endTime;
  final Duration duration;
  final String dominantEmotion;
  final double emotionConfidence;
  final int averageBpm;
  final int minimumBpm;
  final int maximumBpm;
  final String finalState;
  final AiSummaryStatus aiSummaryStatus;
  final AiInsight? aiSummary;
  final String status; // session status: active | completed | cancelled
  final DateTime createdAt;

  const SessionSummary({
    required this.sessionId,
    required this.userId,
    required this.startTime,
    required this.endTime,
    required this.duration,
    required this.dominantEmotion,
    required this.emotionConfidence,
    required this.averageBpm,
    required this.minimumBpm,
    required this.maximumBpm,
    required this.finalState,
    required this.aiSummaryStatus,
    required this.aiSummary,
    required this.status,
    required this.createdAt,
  });

  static const _stressful = {'Angry', 'Fear', 'Disgust'};

  /// Combines facial emotion + heart-rate arousal into a friendly state.
  static String deriveFinalState(String emotion, int avgBpm) {
    final elevated = avgBpm >= 88;
    switch (emotion) {
      case 'Happy':
      case 'Surprise':
        return elevated ? 'Excited' : 'Calm';
      case 'Neutral':
        return 'Calm';
      case 'Sad':
        return 'Low Mood';
      default:
        if (_stressful.contains(emotion)) return elevated ? 'Stressed' : 'Low Mood';
        return 'Neutral';
    }
  }

  factory SessionSummary.fromSession(
    DetectionSession s,
    List<EmotionReading> readings,
  ) {
    final hr = readings.where((r) => r.hr > 0).map((r) => r.hr).toList();
    final avg = hr.isEmpty ? 0 : (hr.reduce((a, b) => a + b) / hr.length).round();
    final min = hr.isEmpty ? 0 : hr.reduce((a, b) => a < b ? a : b);
    final max = hr.isEmpty ? 0 : hr.reduce((a, b) => a > b ? a : b);

    final counts = <String, int>{};
    for (final r in readings) {
      counts[r.emotion] = (counts[r.emotion] ?? 0) + 1;
    }
    final dominant = counts.isEmpty
        ? 'Neutral'
        : counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;

    final domReadings = readings.where((r) => r.emotion == dominant).toList();
    final conf = domReadings.isEmpty
        ? 0.0
        : domReadings.map((r) => r.confidence).reduce((a, b) => a + b) /
            domReadings.length;

    return SessionSummary(
      sessionId: s.sessionId,
      userId: s.userId,
      startTime: s.startTime,
      endTime: s.endTime,
      // Effective span, so an abandoned `active` session shows its real measured
      // length instead of the runaway "now − start".
      duration: effectiveSessionDuration(
        s,
        lastReadingAt: lastReadingTime(readings),
      ),
      dominantEmotion: dominant,
      emotionConfidence: conf,
      averageBpm: avg,
      minimumBpm: min,
      maximumBpm: max,
      finalState: deriveFinalState(dominant, avg),
      aiSummaryStatus:
          AiSummaryStatus.fromRaw(s.aiSummaryStatus, hasSummary: s.aiSummary != null),
      aiSummary: s.aiSummary,
      status: s.status,
      createdAt: s.startTime,
    );
  }

  /// True when the free-text [query] matches this session by id, date, emotion
  /// or final state (case-insensitive).
  bool matches(String query) {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return true;
    final local = startTime.toLocal();
    final haystack = [
      sessionId,
      dominantEmotion,
      finalState,
      DateFormat('dd MMM yyyy').format(local),
      DateFormat('EEEE').format(local),
      DateFormat('h:mm a').format(local),
    ].join(' ').toLowerCase();
    return haystack.contains(q);
  }
}
