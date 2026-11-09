import 'emotion_reading.dart';

/// One emotion's share of the session.
class EmotionShare {
  final String emotion;
  final int count;
  final double percent;
  const EmotionShare(this.emotion, this.count, this.percent);
}

/// A single valid heart-rate sample on the trend.
class HrPoint {
  final DateTime time;
  final int bpm;
  const HrPoint(this.time, this.bpm);
}

/// All the derived numbers the Session Details page shows. Computed once (in a
/// service/controller), never inside `build()`. Pure Dart → unit-testable.
class SessionAnalytics {
  final int totalReadings;
  final int validHrCount;
  final int invalidReadings;

  final String dominantEmotion;
  final int dominantCount;
  final int dominantPercent;

  final int? avgBpm; // null when there's no valid HR
  final int? minBpm;
  final int? maxBpm;

  final int avgConfidence; // 0..100
  final List<EmotionShare> distribution;
  final List<HrPoint> hrTrend;
  final List<EmotionReading> recent; // newest first, up to 5

  final String stressIndicator; // Low | Moderate | Elevated
  final String reliability; // Good | Fair | Limited
  final String sensorQuality; // Good | Fair | Poor

  const SessionAnalytics({
    required this.totalReadings,
    required this.validHrCount,
    required this.invalidReadings,
    required this.dominantEmotion,
    required this.dominantCount,
    required this.dominantPercent,
    required this.avgBpm,
    required this.minBpm,
    required this.maxBpm,
    required this.avgConfidence,
    required this.distribution,
    required this.hrTrend,
    required this.recent,
    required this.stressIndicator,
    required this.reliability,
    required this.sensorQuality,
  });

  bool get hasReadings => totalReadings > 0;
  bool get hasValidHr => validHrCount > 0;

  static const _acceptableHr = {'GOOD', 'HOLDING HR'};
  static const _stressful = {'Angry', 'Fear', 'Sad', 'Disgust'};

  /// Builds analytics from a session's readings (expected oldest→newest, the
  /// order `fetchReadingsForSession` returns).
  factory SessionAnalytics.from(List<EmotionReading> readings) {
    final total = readings.length;
    if (total == 0) {
      return const SessionAnalytics(
        totalReadings: 0,
        validHrCount: 0,
        invalidReadings: 0,
        dominantEmotion: '—',
        dominantCount: 0,
        dominantPercent: 0,
        avgBpm: null,
        minBpm: null,
        maxBpm: null,
        avgConfidence: 0,
        distribution: [],
        hrTrend: [],
        recent: [],
        stressIndicator: 'Low',
        reliability: 'Limited',
        sensorQuality: 'Poor',
      );
    }

    bool validHr(EmotionReading r) =>
        r.hr > 0 && _acceptableHr.contains(r.sensorQuality);

    final hrReadings = readings.where(validHr).toList();
    final hrValues = hrReadings.map((r) => r.hr).toList();

    final counts = <String, int>{};
    for (final r in readings) {
      counts[r.emotion] = (counts[r.emotion] ?? 0) + 1;
    }
    final distribution = counts.entries
        .map((e) => EmotionShare(e.key, e.value, e.value * 100 / total))
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    final dominant = distribution.first;

    final avgConf =
        (readings.map((r) => r.confidence).reduce((a, b) => a + b) / total)
            .round();

    final stressFrac =
        readings.where((r) => _stressful.contains(r.emotion)).length / total;
    final stress = stressFrac < 0.25
        ? 'Low'
        : stressFrac < 0.5
            ? 'Moderate'
            : 'Elevated';

    final goodSensor =
        readings.where((r) => _acceptableHr.contains(r.sensorQuality)).length;
    final sensorRatio = goodSensor / total;
    final sensorQ = sensorRatio >= 0.7
        ? 'Good'
        : sensorRatio >= 0.4
            ? 'Fair'
            : 'Poor';

    final hrRatio = hrReadings.length / total;
    final reliability = (total < 4 || hrRatio < 0.3)
        ? 'Limited'
        : (hrRatio >= 0.6 && avgConf >= 50 && total >= 8)
            ? 'Good'
            : 'Fair';

    return SessionAnalytics(
      totalReadings: total,
      validHrCount: hrReadings.length,
      invalidReadings: total - hrReadings.length,
      dominantEmotion: dominant.emotion,
      dominantCount: dominant.count,
      dominantPercent: dominant.percent.round(),
      avgBpm: hrValues.isEmpty
          ? null
          : (hrValues.reduce((a, b) => a + b) / hrValues.length).round(),
      minBpm: hrValues.isEmpty ? null : hrValues.reduce((a, b) => a < b ? a : b),
      maxBpm: hrValues.isEmpty ? null : hrValues.reduce((a, b) => a > b ? a : b),
      avgConfidence: avgConf,
      distribution: distribution,
      hrTrend: hrReadings.map((r) => HrPoint(r.createdAt, r.hr)).toList(),
      recent: readings.reversed.take(5).toList(),
      stressIndicator: stress,
      reliability: reliability,
      sensorQuality: sensorQ,
    );
  }
}
