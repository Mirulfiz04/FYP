import 'emotion_reading.dart';

/// Granularity for the weekly-trend chart.
enum TrendGranularity { daily, weekly, monthly }

/// One point on the trend chart (a day / week / month bucket).
class TrendPoint {
  final String label;
  final double? bpm; // null when the bucket has no valid HR
  final double? stress; // 1..5, null when the bucket has no data
  const TrendPoint({required this.label, this.bpm, this.stress});
}

/// One slice of the emotion-distribution donut.
class EmotionSlice {
  final String emotion;
  final int count;
  final double percent;
  const EmotionSlice(this.emotion, this.count, this.percent);
}

/// The day + time-of-day window with the highest average stress indicator.
class StressPeriod {
  final String day; // e.g. Wednesday
  final String partOfDay; // e.g. Evening
  final String rangeLabel; // e.g. 6:00 PM – 9:00 PM
  final double stress;
  const StressPeriod({
    required this.day,
    required this.partOfDay,
    required this.rangeLabel,
    required this.stress,
  });
}

/// Everything the Insights screen renders for the selected period. Built by
/// [InsightsCalculator]; pure data (no Flutter).
class InsightsData {
  final int validSessions;
  final int totalValidDetections;

  final int avgBpm;
  final double bpmDeltaPct; // signed, vs previous period
  final double stressIndicator; // 1..5
  final double stressDeltaPct; // signed, vs previous period

  final String dominantEmotion;
  final int dominantPercent;

  final List<EmotionSlice> distribution;
  final List<TrendPoint> trend;

  final String? bestDay;
  final double? bestDayStress;
  final StressPeriod? highestStress;
  final String? emotionalPattern;

  final bool enoughForInsight;

  /// Readings from the valid sessions, for the AI summary (aggregated by
  /// [AiService] — no raw personal data beyond emotion + HR).
  final List<EmotionReading> aiReadings;

  const InsightsData({
    required this.validSessions,
    required this.totalValidDetections,
    required this.avgBpm,
    required this.bpmDeltaPct,
    required this.stressIndicator,
    required this.stressDeltaPct,
    required this.dominantEmotion,
    required this.dominantPercent,
    required this.distribution,
    required this.trend,
    required this.bestDay,
    required this.bestDayStress,
    required this.highestStress,
    required this.emotionalPattern,
    required this.enoughForInsight,
    required this.aiReadings,
  });

  bool get hasData => validSessions > 0;

  static const empty = InsightsData(
    validSessions: 0,
    totalValidDetections: 0,
    avgBpm: 0,
    bpmDeltaPct: 0,
    stressIndicator: 0,
    stressDeltaPct: 0,
    dominantEmotion: '—',
    dominantPercent: 0,
    distribution: [],
    trend: [],
    bestDay: null,
    bestDayStress: null,
    highestStress: null,
    emotionalPattern: null,
    enoughForInsight: false,
    aiReadings: [],
  );
}
