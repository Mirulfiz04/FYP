import 'package:intl/intl.dart';

import 'detection_session.dart';
import 'emotion_reading.dart';
import 'insights_data.dart';
import 'session_liveness.dart';
import 'user_profile.dart';

/// Time window the admin dashboard is showing.
enum DashboardPeriod { today, week, month, custom }

extension DashboardPeriodLabel on DashboardPeriod {
  /// Short label for the period selector chip.
  String get label => switch (this) {
        DashboardPeriod.today => 'Today',
        DashboardPeriod.week => 'This Week',
        DashboardPeriod.month => 'This Month',
        DashboardPeriod.custom => 'Custom',
      };

  /// Friendly "compared with" caption shown under the metric cards.
  String get comparison => switch (this) {
        DashboardPeriod.today => 'vs yesterday',
        DashboardPeriod.week => 'vs last 7d',
        DashboardPeriod.month => 'vs last 30d',
        DashboardPeriod.custom => 'vs prev. period',
      };
}

/// Overall platform health bucket.
enum SystemHealthStatus { healthy, warning, critical }

extension SystemHealthLabel on SystemHealthStatus {
  String get label => switch (this) {
        SystemHealthStatus.healthy => 'Healthy',
        SystemHealthStatus.warning => 'Warning',
        SystemHealthStatus.critical => 'Critical',
      };
}

/// Status shown on a Recent Activity row.
enum ActivityStatus { live, completed, flagged, review }

extension ActivityStatusLabel on ActivityStatus {
  String get label => switch (this) {
        ActivityStatus.live => 'Live',
        ActivityStatus.completed => 'Completed',
        ActivityStatus.flagged => 'Flagged',
        ActivityStatus.review => 'Review',
      };
}

/// A signed percentage change versus the previous, equal-length period.
class MetricTrend {
  final double percent;
  final bool hasBaseline; // false => previous period had no data ("new")

  const MetricTrend(this.percent, {this.hasBaseline = true});

  bool get isUp => percent >= 0;

  static const none = MetricTrend(0, hasBaseline: false);
}

/// The four headline numbers across the top of the dashboard.
class DashboardMetrics {
  final int totalUsers;
  final MetricTrend usersTrend;

  final int activeSessions;
  final MetricTrend sessionsTrend;

  final int aiAlerts; // outstanding AI alerts (failed summaries)
  final int aiAlertsNew; // how many of those appeared this period

  final int systemHealthPercent; // 0..100
  final SystemHealthStatus systemHealthStatus;

  const DashboardMetrics({
    required this.totalUsers,
    required this.usersTrend,
    required this.activeSessions,
    required this.sessionsTrend,
    required this.aiAlerts,
    required this.aiAlertsNew,
    required this.systemHealthPercent,
    required this.systemHealthStatus,
  });

  static const empty = DashboardMetrics(
    totalUsers: 0,
    usersTrend: MetricTrend.none,
    activeSessions: 0,
    sessionsTrend: MetricTrend.none,
    aiAlerts: 0,
    aiAlertsNew: 0,
    systemHealthPercent: 100,
    systemHealthStatus: SystemHealthStatus.healthy,
  );
}

/// One point on the Platform Overview line chart (a time bucket).
class SessionTrendPoint {
  final String label;
  final int sessions;
  const SessionTrendPoint(this.label, this.sessions);
}

/// A single row in the Recent Activity list.
class RecentActivityItem {
  final DetectionSession session;
  final String userName;
  final String initials;
  final String? avatarUrl;
  final ActivityStatus status;

  const RecentActivityItem({
    required this.session,
    required this.userName,
    required this.initials,
    required this.avatarUrl,
    required this.status,
  });

  String get sessionId => session.sessionId;
  DateTime get time => session.startTime.toLocal();

  /// Short, human-friendly session reference (UUIDs are long).
  String get shortId {
    final raw = session.sessionId.replaceAll('-', '');
    final tail = raw.length <= 6 ? raw : raw.substring(raw.length - 6);
    return 'SES-${tail.toUpperCase()}';
  }
}

/// The latest AI wellness insight surfaced on the dashboard.
class DashboardAiInsight {
  final String text;
  final String stressLevel;
  final DateTime? generatedAt;

  const DashboardAiInsight({
    required this.text,
    this.stressLevel = 'Moderate',
    this.generatedAt,
  });
}

/// Everything the Admin Dashboard renders for the selected period. Pure data,
/// built by [DashboardData.build] from rows the service already fetches — so it
/// is fully unit-testable without a database.
class DashboardData {
  final DashboardMetrics metrics;
  final List<SessionTrendPoint> sessionTrend;
  final List<EmotionSlice> emotions;
  final int totalDetections;
  final DashboardAiInsight? aiInsight;
  final bool aiInsightFailed; // a recent AI summary failed and none succeeded
  final List<RecentActivityItem> recentActivity;
  final DashboardPeriod period;

  const DashboardData({
    required this.metrics,
    required this.sessionTrend,
    required this.emotions,
    required this.totalDetections,
    required this.aiInsight,
    required this.aiInsightFailed,
    required this.recentActivity,
    required this.period,
  });

  bool get hasSessionTrendData => sessionTrend.any((p) => p.sessions > 0);

  /// Builds the full dashboard view-model from raw rows.
  static DashboardData build({
    required List<UserProfile> users,
    required List<DetectionSession> sessions,
    required List<EmotionReading> readings,
    required int totalReadings,
    DashboardPeriod period = DashboardPeriod.week,
    DateTime? customStart,
    DateTime? customEnd,
    DateTime? now,
  }) {
    final ref = (now ?? DateTime.now());
    final (start, end) = _window(period, ref, customStart, customEnd);
    final spanMs = end.difference(start).inMilliseconds.clamp(1, 1 << 62);
    final prevStart = start.subtract(Duration(milliseconds: spanMs));

    // Newest reading per session — lets us tell a genuinely-live session from an
    // abandoned `active` row (app closed without ending it).
    final lastReadingBySession = <String, DateTime?>{};
    for (final r in readings) {
      final sid = r.sessionId;
      if (sid == null) continue;
      final cur = lastReadingBySession[sid];
      if (cur == null || r.createdAt.isAfter(cur)) {
        lastReadingBySession[sid] = r.createdAt;
      }
    }

    // ---- Metrics ----------------------------------------------------------
    int usersThis = 0, usersPrev = 0;
    for (final u in users) {
      final c = u.createdAt?.toLocal();
      if (c == null) continue;
      if (_inRange(c, start, end)) {
        usersThis++;
      } else if (_inRange(c, prevStart, start)) {
        usersPrev++;
      }
    }

    int sessThis = 0, sessPrev = 0;
    for (final s in sessions) {
      final t = s.startTime.toLocal();
      if (_inRange(t, start, end)) {
        sessThis++;
      } else if (_inRange(t, prevStart, start)) {
        sessPrev++;
      }
    }

    final activeSessions = sessions
        .where((s) => isSessionLive(s,
            lastReadingAt: lastReadingBySession[s.sessionId], now: ref))
        .length;

    final allFailed =
        sessions.where((s) => s.aiSummaryStatus == 'failed').toList();
    final alertsNew = allFailed.where((s) {
      final t = (s.aiGeneratedAt ?? s.endTime ?? s.startTime).toLocal();
      return _inRange(t, start, end);
    }).length;

    final completed = sessions.where((s) => s.endTime != null).length;
    final failRatio = completed == 0 ? 0.0 : allFailed.length / completed;
    var health = 100.0 - failRatio * 40.0;
    if (totalReadings == 0 && sessions.isNotEmpty) health -= 15;
    if (users.isEmpty) health -= 10;
    final healthPercent = health.clamp(0, 100).round();
    final healthStatus = healthPercent >= 90
        ? SystemHealthStatus.healthy
        : healthPercent >= 70
            ? SystemHealthStatus.warning
            : SystemHealthStatus.critical;

    final metrics = DashboardMetrics(
      totalUsers: users.length,
      usersTrend: _trend(usersPrev, usersThis),
      activeSessions: activeSessions,
      sessionsTrend: _trend(sessPrev, sessThis),
      aiAlerts: allFailed.length,
      aiAlertsNew: alertsNew,
      systemHealthPercent: healthPercent,
      systemHealthStatus: healthStatus,
    );

    // ---- Session trend ----------------------------------------------------
    final trend = _buildTrend(sessions, period, ref, start, end);

    // ---- Emotion distribution (within the period) -------------------------
    final periodReadings = readings
        .where((r) => _inRange(r.createdAt.toLocal(), start, end))
        .toList();
    final emotionCounts = <String, int>{};
    for (final r in periodReadings) {
      emotionCounts[r.emotion] = (emotionCounts[r.emotion] ?? 0) + 1;
    }
    final totalDetections =
        emotionCounts.values.fold<int>(0, (a, b) => a + b);
    final slices = emotionCounts.entries
        .map((e) => EmotionSlice(
            e.key,
            e.value,
            totalDetections == 0 ? 0 : e.value / totalDetections * 100))
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));

    // ---- Latest AI insight ------------------------------------------------
    DashboardAiInsight? insight;
    final withSummary = sessions
        .where((s) =>
            s.aiSummaryStatus == 'completed' && s.aiSummary != null)
        .toList()
      ..sort((a, b) {
        final at = a.aiGeneratedAt ?? a.endTime ?? a.startTime;
        final bt = b.aiGeneratedAt ?? b.endTime ?? b.startTime;
        return bt.compareTo(at);
      });
    if (withSummary.isNotEmpty) {
      final s = withSummary.first;
      insight = DashboardAiInsight(
        text: s.aiSummary!.emotionalSummary,
        stressLevel: s.aiSummary!.stressLevel,
        generatedAt: (s.aiGeneratedAt ?? s.endTime)?.toLocal(),
      );
    }
    final aiFailed = insight == null && allFailed.isNotEmpty;

    // ---- Recent activity --------------------------------------------------
    final byId = {for (final u in users) u.id: u};
    final recent = (List<DetectionSession>.from(sessions)
          ..sort((a, b) => b.startTime.compareTo(a.startTime)))
        .take(6)
        .map((s) {
      final p = byId[s.userId];
      final name = p?.displayLabel ?? 'Unknown user';
      return RecentActivityItem(
        session: s,
        userName: name,
        initials: p?.initials ?? _initialsFrom(name),
        avatarUrl: p?.avatarUrl,
        status: _activityStatus(s,
            lastReadingAt: lastReadingBySession[s.sessionId], now: ref),
      );
    }).toList();

    return DashboardData(
      metrics: metrics,
      sessionTrend: trend,
      emotions: slices,
      totalDetections: totalDetections,
      aiInsight: insight,
      aiInsightFailed: aiFailed,
      recentActivity: recent,
      period: period,
    );
  }
}

// ---------------------------------------------------------------------------
// Pure helpers
// ---------------------------------------------------------------------------

(DateTime, DateTime) _window(
    DashboardPeriod p, DateTime now, DateTime? cs, DateTime? ce) {
  switch (p) {
    case DashboardPeriod.today:
      return (DateTime(now.year, now.month, now.day), now);
    case DashboardPeriod.week:
      return (now.subtract(const Duration(days: 7)), now);
    case DashboardPeriod.month:
      return (now.subtract(const Duration(days: 30)), now);
    case DashboardPeriod.custom:
      final s = cs ?? now.subtract(const Duration(days: 7));
      final e = ce ?? now;
      return (s.isBefore(e) ? s : e, s.isBefore(e) ? e : s);
  }
}

bool _inRange(DateTime t, DateTime start, DateTime end) =>
    !t.isBefore(start) && t.isBefore(end);

MetricTrend _trend(int prev, int now) {
  if (prev == 0) {
    return MetricTrend(now == 0 ? 0 : 100, hasBaseline: false);
  }
  return MetricTrend((now - prev) / prev * 100);
}

List<SessionTrendPoint> _buildTrend(
  List<DetectionSession> sessions,
  DashboardPeriod period,
  DateTime now,
  DateTime start,
  DateTime end,
) {
  switch (period) {
    case DashboardPeriod.today:
      final midnight = DateTime(now.year, now.month, now.day);
      return _equalBuckets(
          sessions, midnight, midnight.add(const Duration(days: 1)), 6,
          (b) => _hourLabel(b));
    case DashboardPeriod.week:
      final startDay = DateTime(now.year, now.month, now.day)
          .subtract(const Duration(days: 6));
      return _equalBuckets(
          sessions, startDay, startDay.add(const Duration(days: 7)), 7,
          (b) => DateFormat('EEE').format(b));
    case DashboardPeriod.month:
      return _equalBuckets(sessions, start, end, 6,
          (b) => DateFormat('d/M').format(b));
    case DashboardPeriod.custom:
      final days = end.difference(start).inDays;
      final count = days.clamp(2, 7);
      return _equalBuckets(
          sessions, start, end, count, (b) => DateFormat('d/M').format(b));
  }
}

/// Splits [start, end) into [count] equal-length buckets and counts sessions
/// whose start time falls into each.
List<SessionTrendPoint> _equalBuckets(
  List<DetectionSession> sessions,
  DateTime start,
  DateTime end,
  int count,
  String Function(DateTime bucketStart) label,
) {
  final totalMs = end.difference(start).inMilliseconds;
  if (totalMs <= 0 || count <= 0) return const [];
  final step = totalMs / count;
  final counts = List<int>.filled(count, 0);
  for (final s in sessions) {
    final t = s.startTime.toLocal();
    if (t.isBefore(start) || !t.isBefore(end)) continue;
    var idx = (t.difference(start).inMilliseconds / step).floor();
    if (idx < 0) idx = 0;
    if (idx >= count) idx = count - 1;
    counts[idx]++;
  }
  return List.generate(count, (i) {
    final bucketStart =
        start.add(Duration(milliseconds: (step * i).round()));
    return SessionTrendPoint(label(bucketStart), counts[i]);
  });
}

String _hourLabel(DateTime d) {
  final h = d.hour;
  final suffix = h < 12 ? 'a' : 'p';
  var hh = h % 12;
  if (hh == 0) hh = 12;
  return '$hh$suffix';
}

ActivityStatus _activityStatus(
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

String _initialsFrom(String source) {
  final parts =
      source.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
  return parts[0][0].toUpperCase();
}
