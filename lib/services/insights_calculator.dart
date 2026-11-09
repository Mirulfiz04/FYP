import 'package:intl/intl.dart';

import '../models/detection_session.dart';
import '../models/emotion_reading.dart';
import '../models/insights_data.dart';

/// One valid session reduced to the numbers the insights need.
class _ValidSession {
  final DateTime date;
  final List<EmotionReading> facial; // confidence >= threshold
  final List<int> hr; // valid heart-rate readings
  final double stress; // 1..5
  final double avgBpm;
  _ValidSession(this.date, this.facial, this.hr, this.stress, this.avgBpm);
}

/// Pure insights math. No Flutter / Supabase / AI — fully unit-testable.
///
/// Data-quality rules applied here:
///   • session status == 'completed'
///   • facial readings counted only when confidence >= [minConfidence]
///   • HR readings counted only when hr > 0 and sensor quality is acceptable
///   • a session is valid only with >= 3 confident facial readings AND >= 1
///     valid HR reading
class InsightsCalculator {
  static const double minConfidence = 40;
  static const Set<String> acceptableQuality = {'GOOD', 'HOLDING HR'};
  static const int minSessionsForInsight = 3;
  static const int minDaysForInsight = 2;
  static const Set<String> _stressful = {'Angry', 'Fear', 'Sad', 'Disgust'};
  static const Set<String> _positive = {'Happy', 'Surprise'};

  static InsightsData compute({
    required List<DetectionSession> sessions,
    required List<EmotionReading> readings,
    required DateTime start,
    required DateTime end,
    required DateTime prevStart,
    required DateTime prevEnd,
    TrendGranularity granularity = TrendGranularity.daily,
  }) {
    final bySession = <String, List<EmotionReading>>{};
    for (final r in readings) {
      final sid = r.sessionId;
      if (sid != null) (bySession[sid] ??= []).add(r);
    }

    List<_ValidSession> validIn(DateTime s, DateTime e, {required bool inclusiveEnd}) {
      final out = <_ValidSession>[];
      for (final sess in sessions) {
        if (sess.status != 'completed') continue;
        final t = sess.startTime.toLocal();
        final inWindow = !t.isBefore(s) && (inclusiveEnd ? !t.isAfter(e) : t.isBefore(e));
        if (!inWindow) continue;
        final rs = bySession[sess.sessionId] ?? const <EmotionReading>[];
        final facial = rs.where((r) => r.confidence >= minConfidence).toList();
        final hr = rs
            .where((r) => r.hr > 0 && acceptableQuality.contains(r.sensorQuality))
            .map((r) => r.hr)
            .toList();
        if (facial.length < 3 || hr.isEmpty) continue;
        final stressFrac =
            facial.where((r) => _stressful.contains(r.emotion)).length /
                facial.length;
        out.add(_ValidSession(
          t,
          facial,
          hr,
          1 + stressFrac * 4,
          hr.reduce((a, b) => a + b) / hr.length,
        ));
      }
      return out;
    }

    final cur = validIn(start, end, inclusiveEnd: true);
    final prev = validIn(prevStart, prevEnd, inclusiveEnd: false);

    if (cur.isEmpty) return InsightsData.empty;

    final curBpm = _avgBpm(cur);
    final prevBpm = _avgBpm(prev);
    final curStress = _avgStress(cur);
    final prevStress = _avgStress(prev);

    // Emotion distribution across valid facial readings.
    final counts = <String, int>{};
    final aiReadings = <EmotionReading>[];
    for (final s in cur) {
      aiReadings.addAll(s.facial);
      for (final r in s.facial) {
        counts[r.emotion] = (counts[r.emotion] ?? 0) + 1;
      }
    }
    final totalDetections = counts.values.fold(0, (a, b) => a + b);
    final distribution = counts.entries
        .map((e) =>
            EmotionSlice(e.key, e.value, e.value * 100 / totalDetections))
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    final dominant = distribution.first;

    final distinctDays = cur.map((s) => _dayKey(s.date)).toSet().length;
    final enough = cur.length >= minSessionsForInsight && distinctDays >= minDaysForInsight;

    return InsightsData(
      validSessions: cur.length,
      totalValidDetections: totalDetections,
      avgBpm: curBpm.round(),
      bpmDeltaPct: _deltaPct(curBpm, prevBpm),
      stressIndicator: double.parse(curStress.toStringAsFixed(1)),
      stressDeltaPct: _deltaPct(curStress, prevStress),
      dominantEmotion: dominant.emotion,
      dominantPercent: dominant.percent.round(),
      distribution: distribution,
      trend: _trend(cur, start, end, granularity),
      bestDay: enough ? _bestDay(cur)?.$1 : null,
      bestDayStress: enough ? _bestDay(cur)?.$2 : null,
      highestStress: enough ? _highestStress(cur) : null,
      emotionalPattern: enough ? _pattern(cur) : null,
      enoughForInsight: enough,
      aiReadings: aiReadings,
    );
  }

  static double _avgBpm(List<_ValidSession> xs) {
    final hr = xs.expand((s) => s.hr).toList();
    if (hr.isEmpty) return 0;
    return hr.reduce((a, b) => a + b) / hr.length;
  }

  static double _avgStress(List<_ValidSession> xs) {
    if (xs.isEmpty) return 0;
    return xs.map((s) => s.stress).reduce((a, b) => a + b) / xs.length;
  }

  static double _deltaPct(double cur, double prev) {
    if (prev <= 0) return 0;
    return double.parse(((cur - prev) / prev * 100).toStringAsFixed(0));
  }

  static List<TrendPoint> _trend(
      List<_ValidSession> cur, DateTime start, DateTime end, TrendGranularity g) {
    String key(DateTime d) => switch (g) {
          TrendGranularity.daily => _dayKey(d),
          TrendGranularity.weekly => _weekKey(d),
          TrendGranularity.monthly => '${d.year}-${d.month}',
        };

    final span = end.difference(start).inDays;
    final buckets = <String, List<_ValidSession>>{};
    final order = <String>[];
    for (final s in cur) {
      final k = key(s.date);
      if (!buckets.containsKey(k)) {
        buckets[k] = [];
        order.add(k);
      }
      buckets[k]!.add(s);
    }
    order.sort();

    String label(_ValidSession sample) => switch (g) {
          TrendGranularity.daily =>
            span <= 7 ? DateFormat('EEE').format(sample.date) : DateFormat('d/M').format(sample.date),
          TrendGranularity.weekly => DateFormat('d/M').format(sample.date),
          TrendGranularity.monthly => DateFormat('MMM').format(sample.date),
        };

    return order.map((k) {
      final xs = buckets[k]!;
      return TrendPoint(
        label: label(xs.first),
        bpm: _avgBpm(xs),
        stress: _avgStress(xs),
      );
    }).toList();
  }

  static (String, double)? _bestDay(List<_ValidSession> cur) {
    final byDay = <int, List<double>>{};
    for (final s in cur) {
      (byDay[s.date.weekday] ??= []).add(s.stress);
    }
    if (byDay.isEmpty) return null;
    int? bestWd;
    double best = double.infinity;
    byDay.forEach((wd, vals) {
      final m = vals.reduce((a, b) => a + b) / vals.length;
      if (m < best) {
        best = m;
        bestWd = wd;
      }
    });
    final name = DateFormat('EEEE')
        .format(DateTime(2024, 1, bestWd!)); // 2024-01-01 is a Monday
    return (name, double.parse(best.toStringAsFixed(1)));
  }

  static StressPeriod? _highestStress(List<_ValidSession> cur) {
    final byBucket = <String, List<double>>{};
    final meta = <String, ({int wd, int hour})>{};
    for (final s in cur) {
      final b = _partOfDay(s.date.hour);
      final k = '${s.date.weekday}-${b.name}';
      (byBucket[k] ??= []).add(s.stress);
      meta[k] = (wd: s.date.weekday, hour: s.date.hour);
    }
    if (byBucket.isEmpty) return null;
    String? bestK;
    double best = -1;
    byBucket.forEach((k, vals) {
      final m = vals.reduce((a, b) => a + b) / vals.length;
      if (m > best) {
        best = m;
        bestK = k;
      }
    });
    final m = meta[bestK]!;
    final b = _partOfDay(m.hour);
    return StressPeriod(
      day: DateFormat('EEEE').format(DateTime(2024, 1, m.wd)),
      partOfDay: b.name,
      rangeLabel: b.range,
      stress: double.parse(best.toStringAsFixed(1)),
    );
  }

  static String _pattern(List<_ValidSession> cur) {
    double posFrac(List<_ValidSession> xs) {
      final all = xs.expand((s) => s.facial).toList();
      if (all.isEmpty) return 0;
      return all.where((r) => _positive.contains(r.emotion)).length / all.length;
    }

    final weekend = cur.where((s) => s.date.weekday >= 6).toList();
    final weekday = cur.where((s) => s.date.weekday < 6).toList();
    final buf = StringBuffer();
    if (weekend.isNotEmpty && weekday.isNotEmpty) {
      final we = posFrac(weekend), wd = posFrac(weekday);
      if (we > wd + 0.05) {
        buf.write('You tend to show more positive emotional patterns on weekends. ');
      } else if (wd > we + 0.05) {
        buf.write('You tend to feel more positive on weekdays. ');
      } else {
        buf.write('Your positivity stays fairly steady through the week. ');
      }
    }
    final hs = _highestStress(cur);
    if (hs != null) {
      buf.write('Your stress indicator was higher during ${hs.day} '
          '${hs.partOfDay.toLowerCase()} sessions.');
    }
    final out = buf.toString().trim();
    return out.isEmpty
        ? 'Keep completing sessions to reveal your emotional patterns.'
        : out;
  }

  static ({String name, String range}) _partOfDay(int hour) {
    if (hour >= 5 && hour < 12) {
      return (name: 'Morning', range: '6:00 AM – 12:00 PM');
    }
    if (hour >= 12 && hour < 17) {
      return (name: 'Afternoon', range: '12:00 PM – 5:00 PM');
    }
    if (hour >= 17 && hour < 21) {
      return (name: 'Evening', range: '6:00 PM – 9:00 PM');
    }
    return (name: 'Night', range: '9:00 PM – 5:00 AM');
  }

  static String _dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  static String _weekKey(DateTime d) {
    final monday = DateTime(d.year, d.month, d.day)
        .subtract(Duration(days: d.weekday - 1));
    return '${monday.year}-${monday.month}-${monday.day}';
  }
}
