import 'package:intl/intl.dart';

import 'detection_session.dart';
import 'emotion_reading.dart';
import 'insights_data.dart';
import 'user_profile.dart';

/// Period selector for the admin Insights screen.
enum AdminInsightsPeriod { today, week, month, quarter, custom }

extension AdminInsightsPeriodInfo on AdminInsightsPeriod {
  String get label => switch (this) {
        AdminInsightsPeriod.today => 'Today',
        AdminInsightsPeriod.week => 'This Week',
        AdminInsightsPeriod.month => 'This Month',
        AdminInsightsPeriod.quarter => 'This Quarter',
        AdminInsightsPeriod.custom => 'Custom',
      };

  String get comparison => switch (this) {
        AdminInsightsPeriod.today => 'vs yesterday',
        AdminInsightsPeriod.week => 'vs last week',
        AdminInsightsPeriod.month => 'vs last month',
        AdminInsightsPeriod.quarter => 'vs last quarter',
        AdminInsightsPeriod.custom => 'vs prev. period',
      };
}

/// Risk level for an at-risk user.
enum RiskLevel { high, elevated, low }

extension RiskLevelInfo on RiskLevel {
  String get label => switch (this) {
        RiskLevel.high => 'High',
        RiskLevel.elevated => 'Elevated',
        RiskLevel.low => 'Low',
      };

  int get priority => switch (this) {
        RiskLevel.high => 2,
        RiskLevel.elevated => 1,
        RiskLevel.low => 0,
      };
}

/// One point on the weekly trend chart.
class TrendDatum {
  final DateTime date;
  final String dayLabel; // e.g. "Mon" or "12 May"
  final String dateLabel; // e.g. "May 12" (blank for weekly/monthly buckets)
  final double stress; // 0..100
  final double bpm;

  const TrendDatum({
    required this.date,
    required this.dayLabel,
    required this.dateLabel,
    required this.stress,
    required this.bpm,
  });
}

/// A user flagged as at-risk by the analytics.
class RiskUser {
  final String userId;
  final String name;
  final String? avatarUrl;
  final String initials;
  final String indicator; // "High Stress", "High Heart Rate", …
  final DateTime time;
  final RiskLevel risk;
  final DetectionSession? latestSession;

  const RiskUser({
    required this.userId,
    required this.name,
    required this.avatarUrl,
    required this.initials,
    required this.indicator,
    required this.time,
    required this.risk,
    required this.latestSession,
  });
}

/// Platform session-performance metrics.
class SessionPerformance {
  final double completionRate; // 0..100
  final double completionDelta; // percentage points vs previous period
  final double aiReviewedRate; // 0..100
  final double aiReviewedDelta;
  final double? avgDetectionSeconds; // null when not derivable
  final double? detectionDelta; // negative = faster (improved)

  const SessionPerformance({
    required this.completionRate,
    required this.completionDelta,
    required this.aiReviewedRate,
    required this.aiReviewedDelta,
    required this.avgDetectionSeconds,
    required this.detectionDelta,
  });

  static const empty = SessionPerformance(
    completionRate: 0,
    completionDelta: 0,
    aiReviewedRate: 0,
    aiReviewedDelta: 0,
    avgDetectionSeconds: null,
    detectionDelta: null,
  );
}

/// Everything the admin Insights screen renders for the selected period. Pure
/// data built by [AdminInsightsData.build] — fully unit-testable, no DB.
class AdminInsightsData {
  final int avgStress; // 0..100
  final double avgStressDeltaPct;
  final int avgBpm;
  final double avgBpmDeltaPct;
  final String dominantEmotion;
  final int dominantPercent;
  final int flagged;
  final double flaggedDeltaPct;

  final List<TrendDatum> trend;

  final List<EmotionSlice> emotions;
  final int totalSessions; // shown in the donut centre

  final String aiText;
  final String highestStressDay;

  final List<RiskUser> atRiskUsers;
  final SessionPerformance performance;

  final bool hasData;

  const AdminInsightsData({
    required this.avgStress,
    required this.avgStressDeltaPct,
    required this.avgBpm,
    required this.avgBpmDeltaPct,
    required this.dominantEmotion,
    required this.dominantPercent,
    required this.flagged,
    required this.flaggedDeltaPct,
    required this.trend,
    required this.emotions,
    required this.totalSessions,
    required this.aiText,
    required this.highestStressDay,
    required this.atRiskUsers,
    required this.performance,
    required this.hasData,
  });

  static const empty = AdminInsightsData(
    avgStress: 0,
    avgStressDeltaPct: 0,
    avgBpm: 0,
    avgBpmDeltaPct: 0,
    dominantEmotion: '—',
    dominantPercent: 0,
    flagged: 0,
    flaggedDeltaPct: 0,
    trend: [],
    emotions: [],
    totalSessions: 0,
    aiText:
        'Not enough completed sessions with valid emotion and heart-rate data '
        'to analyse trends for this period yet.',
    highestStressDay: '—',
    atRiskUsers: [],
    performance: SessionPerformance.empty,
    hasData: false,
  );

  static AdminInsightsData build({
    required List<UserProfile> users,
    required List<DetectionSession> sessions,
    required List<EmotionReading> readings,
    AdminInsightsPeriod period = AdminInsightsPeriod.week,
    DateTime? customStart,
    DateTime? customEnd,
    DateTime? now,
  }) {
    final ref = now ?? DateTime.now();
    final (start, end) = _window(period, ref, customStart, customEnd);
    final spanMs = end.difference(start).inMilliseconds.clamp(1, 1 << 62);
    final prevStart = start.subtract(Duration(milliseconds: spanMs));

    final bySession = <String, List<EmotionReading>>{};
    for (final r in readings) {
      final sid = r.sessionId;
      if (sid != null) (bySession[sid] ??= []).add(r);
    }

    final aggs =
        sessions.map((s) => _SessAgg.of(s, bySession[s.sessionId] ?? const []));

    bool inPeriod(_SessAgg a) => _inRange(a.date, start, end);
    bool inPrev(_SessAgg a) => _inRange(a.date, prevStart, start);

    final periodAll = aggs.where(inPeriod).toList();
    final prevAll = aggs.where(inPrev).toList();
    final curValid = periodAll.where((a) => a.valid).toList();
    final prevValid = prevAll.where((a) => a.valid).toList();

    // ---- Summary metrics --------------------------------------------------
    final avgStress = _mean(curValid.map((a) => a.stress100));
    final prevStress = _mean(prevValid.map((a) => a.stress100));
    final avgBpm = _mean(curValid.map((a) => a.avgBpm));
    final prevBpm = _mean(prevValid.map((a) => a.avgBpm));

    // ---- Emotion distribution --------------------------------------------
    final counts = <String, int>{};
    for (final a in curValid) {
      for (final r in a.facial) {
        counts[r.emotion] = (counts[r.emotion] ?? 0) + 1;
      }
    }
    final totalDetections = counts.values.fold<int>(0, (x, y) => x + y);
    final slices = counts.entries
        .map((e) => EmotionSlice(e.key, e.value,
            totalDetections == 0 ? 0 : e.value / totalDetections * 100))
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    final dominant = slices.isEmpty ? null : slices.first;

    // ---- Trend ------------------------------------------------------------
    final trend = _buildTrend(curValid, period, start, end);
    final highestStressDay = _highestStressDay(trend);

    // ---- Flagged sessions -------------------------------------------------
    int flaggedIn(List<_SessAgg> xs) => xs.where((a) => a.isFlagged).length;
    final flagged = flaggedIn(periodAll);
    final flaggedPrev = flaggedIn(prevAll);

    // ---- At-risk users ----------------------------------------------------
    final atRisk = _atRiskUsers(curValid, users);

    // ---- Session performance ---------------------------------------------
    final performance = _performance(periodAll, prevAll);

    // ---- AI narrative -----------------------------------------------------
    final aiText = _aiText(
      hasData: curValid.isNotEmpty,
      stressDelta: _deltaPct(avgStress, prevStress),
      highestStressDay: highestStressDay,
      flagged: flagged,
    );

    return AdminInsightsData(
      avgStress: avgStress.round(),
      avgStressDeltaPct: _deltaPct(avgStress, prevStress),
      avgBpm: avgBpm.round(),
      avgBpmDeltaPct: _deltaPct(avgBpm, prevBpm),
      dominantEmotion: dominant?.emotion ?? '—',
      dominantPercent: dominant?.percent.round() ?? 0,
      flagged: flagged,
      flaggedDeltaPct: _deltaPct(flagged.toDouble(), flaggedPrev.toDouble()),
      trend: trend,
      emotions: slices,
      totalSessions: periodAll.length,
      aiText: aiText,
      highestStressDay: highestStressDay,
      atRiskUsers: atRisk,
      performance: performance,
      hasData: periodAll.isNotEmpty,
    );
  }
}

// ---------------------------------------------------------------------------
// Per-session reduction
// ---------------------------------------------------------------------------

const double _minConfidence = 40;
const Set<String> _acceptableQuality = {'GOOD', 'HOLDING HR'};
const Set<String> _stressful = {'Angry', 'Fear', 'Sad', 'Disgust'};

class _SessAgg {
  final DetectionSession session;
  final DateTime date;
  final String userId;
  final bool valid;
  final double stress100; // 0..100
  final double avgBpm;
  final List<EmotionReading> facial;
  final double? gapSeconds; // mean interval between readings

  _SessAgg({
    required this.session,
    required this.date,
    required this.userId,
    required this.valid,
    required this.stress100,
    required this.avgBpm,
    required this.facial,
    required this.gapSeconds,
  });

  String get status => session.status;
  String get aiStatus => session.aiSummaryStatus;
  String? get aiStress => session.aiSummary?.stressLevel;

  bool get isFlagged =>
      aiStatus == 'failed' || aiStress == 'High' || aiStress == 'Elevated';

  factory _SessAgg.of(DetectionSession s, List<EmotionReading> rs) {
    final facial =
        rs.where((r) => r.confidence >= _minConfidence).toList();
    final hr = rs
        .where((r) => r.hr > 0 && _acceptableQuality.contains(r.sensorQuality))
        .map((r) => r.hr)
        .toList();
    final valid =
        s.status == 'completed' && facial.length >= 3 && hr.isNotEmpty;
    final stressFrac = facial.isEmpty
        ? 0.0
        : facial.where((r) => _stressful.contains(r.emotion)).length /
            facial.length;
    final avgBpm =
        hr.isEmpty ? 0.0 : hr.reduce((a, b) => a + b) / hr.length;

    return _SessAgg(
      session: s,
      date: s.startTime.toLocal(),
      userId: s.userId,
      valid: valid,
      stress100: stressFrac * 100,
      avgBpm: avgBpm,
      facial: facial,
      gapSeconds: _meanGap(rs),
    );
  }
}

double? _meanGap(List<EmotionReading> rs) {
  if (rs.length < 2) return null;
  final times = rs.map((r) => r.createdAt).toList()..sort();
  var total = 0.0;
  for (var i = 1; i < times.length; i++) {
    total += times[i].difference(times[i - 1]).inMilliseconds / 1000.0;
  }
  final mean = total / (times.length - 1);
  return mean.clamp(0.2, 30.0);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

(DateTime, DateTime) _window(
    AdminInsightsPeriod p, DateTime now, DateTime? cs, DateTime? ce) {
  switch (p) {
    case AdminInsightsPeriod.today:
      return (DateTime(now.year, now.month, now.day), now);
    case AdminInsightsPeriod.week:
      return (now.subtract(const Duration(days: 7)), now);
    case AdminInsightsPeriod.month:
      return (now.subtract(const Duration(days: 30)), now);
    case AdminInsightsPeriod.quarter:
      return (now.subtract(const Duration(days: 90)), now);
    case AdminInsightsPeriod.custom:
      final s = cs ?? now.subtract(const Duration(days: 7));
      final e = ce ?? now;
      return (s.isBefore(e) ? s : e, s.isBefore(e) ? e : s);
  }
}

bool _inRange(DateTime t, DateTime start, DateTime end) =>
    !t.isBefore(start) && t.isBefore(end);

double _mean(Iterable<double> xs) {
  final list = xs.toList();
  if (list.isEmpty) return 0;
  return list.reduce((a, b) => a + b) / list.length;
}

double _deltaPct(double cur, double prev) {
  if (prev <= 0) return 0;
  return double.parse(((cur - prev) / prev * 100).toStringAsFixed(0));
}

enum _Bucket { daily, weekly, monthly }

List<TrendDatum> _buildTrend(
    List<_SessAgg> valid, AdminInsightsPeriod period, DateTime start, DateTime end) {
  if (valid.isEmpty) return const [];
  final spanDays = end.difference(start).inDays;
  final mode = switch (period) {
    AdminInsightsPeriod.today => _Bucket.daily,
    AdminInsightsPeriod.week => _Bucket.daily,
    AdminInsightsPeriod.month => _Bucket.weekly,
    AdminInsightsPeriod.quarter => _Bucket.monthly,
    AdminInsightsPeriod.custom => spanDays <= 8 ? _Bucket.daily : _Bucket.weekly,
  };

  DateTime keyDate(DateTime d) {
    switch (mode) {
      case _Bucket.daily:
        return DateTime(d.year, d.month, d.day);
      case _Bucket.weekly:
        final monday =
            DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));
        return monday;
      case _Bucket.monthly:
        return DateTime(d.year, d.month);
    }
  }

  final buckets = <DateTime, List<_SessAgg>>{};
  for (final a in valid) {
    (buckets[keyDate(a.date)] ??= []).add(a);
  }
  final keys = buckets.keys.toList()..sort();

  return keys.map((k) {
    final xs = buckets[k]!;
    final (dayLabel, dateLabel) = switch (mode) {
      _Bucket.daily => (DateFormat('EEE').format(k), DateFormat('MMM d').format(k)),
      _Bucket.weekly => (DateFormat('MMM d').format(k), ''),
      _Bucket.monthly => (DateFormat('MMM').format(k), ''),
    };
    return TrendDatum(
      date: k,
      dayLabel: dayLabel,
      dateLabel: dateLabel,
      stress: _mean(xs.map((a) => a.stress100)),
      bpm: _mean(xs.map((a) => a.avgBpm)),
    );
  }).toList();
}

String _highestStressDay(List<TrendDatum> trend) {
  if (trend.isEmpty) return '—';
  final top = trend.reduce((a, b) => a.stress >= b.stress ? a : b);
  return DateFormat('EEEE').format(top.date);
}

List<RiskUser> _atRiskUsers(List<_SessAgg> valid, List<UserProfile> users) {
  final byId = {for (final u in users) u.id: u};
  final grouped = <String, List<_SessAgg>>{};
  for (final a in valid) {
    (grouped[a.userId] ??= []).add(a);
  }

  final out = <RiskUser>[];
  grouped.forEach((userId, xs) {
    xs.sort((a, b) => b.date.compareTo(a.date));
    final maxStress = xs.map((a) => a.stress100).reduce((a, b) => a > b ? a : b);
    final avgBpm = _mean(xs.map((a) => a.avgBpm));
    final hasHigh = xs.any((a) => a.aiStress == 'High');
    final hasElev = xs.any((a) => a.aiStress == 'Elevated');

    final RiskLevel risk;
    if (hasHigh || maxStress >= 70 || avgBpm >= 105) {
      risk = RiskLevel.high;
    } else if (hasElev || maxStress >= 45 || avgBpm >= 95) {
      risk = RiskLevel.elevated;
    } else {
      risk = RiskLevel.low;
    }
    if (risk == RiskLevel.low) return;

    final String indicator;
    if (avgBpm >= 100) {
      indicator = 'High Heart Rate';
    } else if (risk == RiskLevel.high) {
      indicator = 'High Stress';
    } else {
      indicator = 'Elevated Stress';
    }

    final profile = byId[userId];
    out.add(RiskUser(
      userId: userId,
      name: profile?.displayLabel ?? 'Unknown user',
      avatarUrl: profile?.avatarUrl,
      initials: profile?.initials ?? '?',
      indicator: indicator,
      time: xs.first.date,
      risk: risk,
      latestSession: xs.first.session,
    ));
  });

  out.sort((a, b) {
    final byRisk = b.risk.priority.compareTo(a.risk.priority);
    if (byRisk != 0) return byRisk;
    return b.time.compareTo(a.time);
  });
  return out.take(5).toList();
}

SessionPerformance _performance(List<_SessAgg> cur, List<_SessAgg> prev) {
  double completion(List<_SessAgg> xs) => xs.isEmpty
      ? 0
      : xs.where((a) => a.status == 'completed').length / xs.length * 100;

  double aiReviewed(List<_SessAgg> xs) {
    final completed = xs.where((a) => a.status == 'completed').toList();
    if (completed.isEmpty) return 0;
    return completed.where((a) => a.aiStatus == 'completed').length /
        completed.length *
        100;
  }

  double? detection(List<_SessAgg> xs) {
    final gaps = xs.map((a) => a.gapSeconds).whereType<double>().toList();
    if (gaps.isEmpty) return null;
    return double.parse(_mean(gaps).toStringAsFixed(1));
  }

  final curCompletion = completion(cur);
  final curAi = aiReviewed(cur);
  final curDet = detection(cur);
  final prevDet = detection(prev);

  return SessionPerformance(
    completionRate: curCompletion,
    completionDelta:
        double.parse((curCompletion - completion(prev)).toStringAsFixed(0)),
    aiReviewedRate: curAi,
    aiReviewedDelta:
        double.parse((curAi - aiReviewed(prev)).toStringAsFixed(0)),
    avgDetectionSeconds: curDet,
    detectionDelta: (curDet != null && prevDet != null)
        ? double.parse((curDet - prevDet).toStringAsFixed(1))
        : null,
  );
}

String _aiText({
  required bool hasData,
  required double stressDelta,
  required String highestStressDay,
  required int flagged,
}) {
  if (!hasData) {
    return 'Not enough completed sessions with valid emotion and heart-rate '
        'data to analyse trends for this period yet.';
  }
  final direction = stressDelta > 3
      ? 'increased'
      : stressDelta < -3
          ? 'eased'
          : 'stayed broadly steady';
  final peak = highestStressDay == '—'
      ? ''
      : ', peaking on $highestStressDay';
  final flaggedText = flagged == 0
      ? 'No sessions were flagged for high stress indicators or irregular '
          'heart-rate readings.'
      : '$flagged session${flagged == 1 ? ' was' : 's were'} flagged for high '
          'stress indicators or irregular heart-rate readings.';
  return 'Average stress levels $direction across the period$peak. $flaggedText';
}
