import 'detection_session.dart';
import 'emotion_reading.dart';

/// One point on the heart-rate trend (seconds since session start → bpm).
class HrPoint {
  final double seconds;
  final int bpm;
  const HrPoint(this.seconds, this.bpm);
}

/// A contiguous stretch of one emotion on the emotion timeline.
class EmotionSegment {
  final String emotion;
  final double startSec;
  final double endSec;
  const EmotionSegment(this.emotion, this.startSec, this.endSec);
}

/// Aggregated, read-only analytics for one monitoring session. Pure data built
/// from the session row + its readings — fully unit-testable, no Supabase.
class SessionDetailData {
  final int avgBpm;
  final int peakBpm;
  final String dominantEmotion; // '—' when no readings
  final String finalState; // Calm | Neutral | Stressed | '—'
  final String sensorQuality; // Good | Fair | Poor | '—'
  final int readingCount;
  final Duration duration;
  final List<HrPoint> hrTrend;
  final List<EmotionSegment> emotionTimeline;

  /// AI wellness summary text, when one has been generated.
  final String? aiSummary;
  final String aiStatus; // pending | processing | completed | failed

  const SessionDetailData({
    required this.avgBpm,
    required this.peakBpm,
    required this.dominantEmotion,
    required this.finalState,
    required this.sensorQuality,
    required this.readingCount,
    required this.duration,
    required this.hrTrend,
    required this.emotionTimeline,
    required this.aiSummary,
    required this.aiStatus,
  });

  bool get hasReadings => readingCount > 0;

  static SessionDetailData empty() => const SessionDetailData(
        avgBpm: 0,
        peakBpm: 0,
        dominantEmotion: '—',
        finalState: '—',
        sensorQuality: '—',
        readingCount: 0,
        duration: Duration.zero,
        hrTrend: [],
        emotionTimeline: [],
        aiSummary: null,
        aiStatus: 'pending',
      );

  static const _calm = {'Happy', 'Neutral', 'Surprise'};
  static const _stress = {'Angry', 'Fear', 'Sad', 'Disgust'};
  static const _acceptableQuality = {'GOOD', 'HOLDING HR'};

  static SessionDetailData build({
    required DetectionSession session,
    required List<EmotionReading> readings,
  }) {
    final origin = session.startTime;
    final sorted = List<EmotionReading>.from(readings)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    final duration = session.endTime != null
        ? session.duration
        : (sorted.isEmpty
            ? Duration.zero
            : sorted.last.createdAt.difference(origin));

    final hr = sorted.where((r) => r.hr > 0).map((r) => r.hr).toList();
    final avgBpm =
        hr.isEmpty ? 0 : (hr.reduce((a, b) => a + b) / hr.length).round();
    final peakBpm = hr.isEmpty ? 0 : hr.reduce((a, b) => a > b ? a : b);

    final hrTrend = <HrPoint>[
      for (final r in sorted)
        if (r.hr > 0)
          HrPoint(
            r.createdAt.difference(origin).inSeconds
                .clamp(0, 1 << 31)
                .toDouble(),
            r.hr,
          ),
    ];

    final counts = <String, int>{};
    for (final r in sorted) {
      counts[r.emotion] = (counts[r.emotion] ?? 0) + 1;
    }
    final dominant = counts.isEmpty
        ? '—'
        : (counts.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value)))
            .first
            .key;

    final quality = _quality(sorted);
    final finalState = _finalState(sorted, origin, duration);
    final timeline = _timeline(sorted, origin, duration);

    return SessionDetailData(
      avgBpm: avgBpm,
      peakBpm: peakBpm,
      dominantEmotion: dominant,
      finalState: finalState,
      sensorQuality: quality,
      readingCount: sorted.length,
      duration: duration,
      hrTrend: hrTrend,
      emotionTimeline: timeline,
      aiSummary: session.aiSummary?.emotionalSummary.trim().isNotEmpty == true
          ? session.aiSummary!.emotionalSummary.trim()
          : null,
      aiStatus: session.aiSummaryStatus,
    );
  }

  static String _quality(List<EmotionReading> rs) {
    if (rs.isEmpty) return '—';
    final ok = rs.where((r) => _acceptableQuality.contains(r.sensorQuality)).length;
    final ratio = ok / rs.length;
    if (ratio >= 0.8) return 'Good';
    if (ratio >= 0.5) return 'Fair';
    return 'Poor';
  }

  static String _finalState(
      List<EmotionReading> rs, DateTime origin, Duration duration) {
    if (rs.isEmpty) return '—';
    final total = duration.inSeconds;
    final cutoff = total <= 0
        ? origin
        : origin.add(Duration(seconds: (total * 0.75).round()));
    var last = rs.where((r) => !r.createdAt.isBefore(cutoff)).toList();
    if (last.isEmpty) last = rs;

    final counts = <String, int>{};
    for (final r in last) {
      counts[r.emotion] = (counts[r.emotion] ?? 0) + 1;
    }
    final dom = (counts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .first
        .key;
    final hr = last.where((r) => r.hr > 0).map((r) => r.hr).toList();
    final avgHr = hr.isEmpty ? 0 : hr.reduce((a, b) => a + b) / hr.length;

    if (_stress.contains(dom) || avgHr >= 100) return 'Stressed';
    if (_calm.contains(dom) && avgHr < 90) return 'Calm';
    return 'Neutral';
  }

  static List<EmotionSegment> _timeline(
      List<EmotionReading> rs, DateTime origin, Duration duration) {
    if (rs.isEmpty) return const [];
    final total = duration.inSeconds <= 0 ? 1 : duration.inSeconds;
    const buckets = 4;
    final step = total / buckets;

    // Dominant emotion per equal time-quarter.
    final perBucket = <String?>[];
    for (var i = 0; i < buckets; i++) {
      final start = origin.add(Duration(seconds: (step * i).round()));
      final end = origin.add(Duration(seconds: (step * (i + 1)).round()));
      final inBucket = rs.where((r) =>
          !r.createdAt.isBefore(start) &&
          (i == buckets - 1 ? true : r.createdAt.isBefore(end)));
      final counts = <String, int>{};
      for (final r in inBucket) {
        counts[r.emotion] = (counts[r.emotion] ?? 0) + 1;
      }
      perBucket.add(counts.isEmpty
          ? null
          : (counts.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value)))
              .first
              .key);
    }

    // Fill empty buckets with the nearest known emotion, then merge runs.
    for (var i = 0; i < buckets; i++) {
      perBucket[i] ??= perBucket.firstWhere((e) => e != null, orElse: () => '—');
    }

    final segments = <EmotionSegment>[];
    var runStart = 0;
    for (var i = 1; i <= buckets; i++) {
      if (i == buckets || perBucket[i] != perBucket[runStart]) {
        segments.add(EmotionSegment(
          perBucket[runStart]!,
          (step * runStart),
          (step * i),
        ));
        runStart = i;
      }
    }
    return segments;
  }
}
