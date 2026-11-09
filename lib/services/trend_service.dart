import '../models/emotion_reading.dart';

/// Per-session aggregate used by the weekly-trend engine.
class SessionStat {
  final DateTime date; // session start, local time
  final double avgBpm; // 0 when no valid HR
  final double stressScore; // 0..1 (fraction of stressful readings)
  final String dominantEmotion;
  final bool valid; // passed quality / confidence filters

  const SessionStat({
    required this.date,
    required this.avgBpm,
    required this.stressScore,
    required this.dominantEmotion,
    required this.valid,
  });

  static const _stressful = {'Angry', 'Fear', 'Sad', 'Disgust'};

  /// Builds a stat from one session's readings. Marks the session invalid when
  /// it lacks reliable facial-emotion AND heart-rate data, so the trend ignores
  /// poor-quality sessions.
  factory SessionStat.fromReadings(
    DateTime date,
    List<EmotionReading> readings, {
    double minConfidence = 40,
  }) {
    final confident =
        readings.where((r) => r.confidence >= minConfidence).toList();
    final hr = readings.where((r) => r.hr > 0).map((r) => r.hr).toList();

    final valid = confident.length >= 3 && hr.isNotEmpty;

    final avgBpm = hr.isEmpty
        ? 0.0
        : hr.reduce((a, b) => a + b) / hr.length;

    final base = confident.isEmpty ? readings : confident;
    final stressCount = base.where((r) => _stressful.contains(r.emotion)).length;
    final stressScore = base.isEmpty ? 0.0 : stressCount / base.length;

    final counts = <String, int>{};
    for (final r in base) {
      counts[r.emotion] = (counts[r.emotion] ?? 0) + 1;
    }
    final dominant = counts.isEmpty
        ? 'Neutral'
        : counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;

    return SessionStat(
      date: date,
      avgBpm: avgBpm,
      stressScore: stressScore,
      dominantEmotion: dominant,
      valid: valid,
    );
  }
}

enum TrendDirection { improved, stable, worsened, insufficient }

/// The result of a weekly-trend evaluation.
class TrendEvaluation {
  final bool enough;
  final TrendDirection direction;
  final String message;
  final String? evidence;
  final int sessionsThisWeek;
  final int bpmDiff; // this week minus last week (rounded)
  final String? dominantEmotion;

  const TrendEvaluation({
    required this.enough,
    required this.direction,
    required this.message,
    this.evidence,
    this.sessionsThisWeek = 0,
    this.bpmDiff = 0,
    this.dominantEmotion,
  });

  static const _insufficientMessage =
      'More sessions are needed to generate a reliable trend';

  factory TrendEvaluation.insufficient() => const TrendEvaluation(
        enough: false,
        direction: TrendDirection.insufficient,
        message: _insufficientMessage,
      );
}

/// Pure weekly-trend logic. No Flutter / Supabase imports → unit-testable.
class TrendService {
  static const int minSessions = 5;
  static const int minDistinctDays = 2;
  static const double _stressThreshold = 0.08;

  /// Compares the current 7-day window with the previous 7-day window.
  ///
  /// Returns [TrendEvaluation.insufficient] (no notification) unless there are
  /// at least [minSessions] valid sessions spanning [minDistinctDays] days AND
  /// both weekly windows contain valid data to compare.
  static TrendEvaluation evaluate(List<SessionStat> stats, {DateTime? now}) {
    final clock = now ?? DateTime.now();
    final valid = stats.where((s) => s.valid).toList();

    final distinctDays =
        valid.map((s) => _dayKey(s.date)).toSet().length;
    if (valid.length < minSessions || distinctDays < minDistinctDays) {
      return TrendEvaluation.insufficient();
    }

    final weekAgo = clock.subtract(const Duration(days: 7));
    final twoWeeksAgo = clock.subtract(const Duration(days: 14));

    final thisWeek = valid
        .where((s) => s.date.isAfter(weekAgo) && !s.date.isAfter(clock))
        .toList();
    final lastWeek = valid
        .where((s) =>
            s.date.isAfter(twoWeeksAgo) && !s.date.isAfter(weekAgo))
        .toList();

    if (thisWeek.isEmpty || lastWeek.isEmpty) {
      return TrendEvaluation.insufficient();
    }

    final stressThis = _mean(thisWeek.map((s) => s.stressScore));
    final stressLast = _mean(lastWeek.map((s) => s.stressScore));
    final delta = stressThis - stressLast;

    final bpmThis = _mean(thisWeek.where((s) => s.avgBpm > 0).map((s) => s.avgBpm));
    final bpmLast = _mean(lastWeek.where((s) => s.avgBpm > 0).map((s) => s.avgBpm));
    final bpmDiff = (bpmThis - bpmLast).round();

    final dominant = _mode(thisWeek.map((s) => s.dominantEmotion));

    final TrendDirection direction;
    final String message;
    if (delta <= -_stressThreshold) {
      direction = TrendDirection.improved;
      message =
          'Your average stress indicator was lower this week than last week.';
    } else if (delta >= _stressThreshold) {
      direction = TrendDirection.worsened;
      message =
          'Your average stress indicator increased this week. Review your recent session insights.';
    } else {
      direction = TrendDirection.stable;
      message = 'Your emotional pattern remained stable this week.';
    }

    final sign = bpmDiff >= 0 ? '+' : '';
    final evidence =
        '${thisWeek.length} sessions this week · avg BPM $sign$bpmDiff vs last week · mostly $dominant';

    return TrendEvaluation(
      enough: true,
      direction: direction,
      message: message,
      evidence: evidence,
      sessionsThisWeek: thisWeek.length,
      bpmDiff: bpmDiff,
      dominantEmotion: dominant,
    );
  }

  /// True when [now] falls in a different calendar week than [lastNotified],
  /// enforcing "at most one trend notification per week".
  static bool isNewWeek(DateTime now, DateTime? lastNotified) {
    if (lastNotified == null) return true;
    return _weekKey(now) != _weekKey(lastNotified);
  }

  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month}-${d.day}';

  /// The Monday of [d]'s week, as a stable key.
  static String _weekKey(DateTime d) {
    final monday = DateTime(d.year, d.month, d.day)
        .subtract(Duration(days: d.weekday - 1));
    return '${monday.year}-${monday.month}-${monday.day}';
  }

  static double _mean(Iterable<double> xs) {
    final list = xs.toList();
    if (list.isEmpty) return 0;
    return list.reduce((a, b) => a + b) / list.length;
  }

  static String _mode(Iterable<String> xs) {
    final counts = <String, int>{};
    for (final x in xs) {
      counts[x] = (counts[x] ?? 0) + 1;
    }
    if (counts.isEmpty) return 'Neutral';
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }
}
