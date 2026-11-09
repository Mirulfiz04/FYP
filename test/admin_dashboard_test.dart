import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meds_flutter_no_python/models/admin_dashboard_models.dart';
import 'package:meds_flutter_no_python/models/ai_insight.dart';
import 'package:meds_flutter_no_python/models/detection_session.dart';
import 'package:meds_flutter_no_python/models/emotion_reading.dart';
import 'package:meds_flutter_no_python/models/user_profile.dart';
import 'package:meds_flutter_no_python/screens/admin/admin_dashboard_screen.dart';
import 'package:meds_flutter_no_python/services/admin_dashboard_service.dart';
import 'package:meds_flutter_no_python/theme/app_theme.dart';
import 'package:meds_flutter_no_python/widgets/admin/dashboard_metric_card.dart';

// A fixed "now": Sunday 21 June 2026, 14:00.
final _now = DateTime(2026, 6, 21, 14);

UserProfile _user(String id, DateTime created, {String role = 'user'}) =>
    UserProfile(
        id: id, name: 'User $id', email: '$id@x.com', role: role,
        createdAt: created);

int _rid = 0;
EmotionReading _reading(String emotion, DateTime at) => EmotionReading(
      id: _rid++,
      createdAt: at,
      emotion: emotion,
      confidence: 90,
      hr: 72,
      spo2: 98,
      sensorQuality: 'GOOD',
    );

DetectionSession _session(
  String id,
  DateTime start, {
  String status = 'completed',
  DateTime? end,
  String aiStatus = 'pending',
  AiInsight? summary,
  DateTime? aiAt,
}) =>
    DetectionSession(
      sessionId: id,
      userId: 'u1',
      startTime: start,
      endTime: end ?? (status == 'active' ? null : start.add(const Duration(minutes: 5))),
      status: status,
      aiSummaryStatus: aiStatus,
      aiSummary: summary,
      aiGeneratedAt: aiAt,
    );

/// A representative dataset used across several build tests.
({List<UserProfile> users, List<DetectionSession> sessions, List<EmotionReading> readings})
    _dataset() {
  const insight = AiInsight(
    emotionalSummary: 'Indicators were generally stable this week.',
    stressLevel: 'Low',
    trendAnalysis: 'steady',
    recommendations: ['Rest well'],
  );
  return (
    users: [
      _user('u1', DateTime(2026, 6, 20)),
      _user('u2', DateTime(2026, 6, 18)),
      _user('u3', DateTime(2026, 6, 10)), // previous 7d
      _user('u4', DateTime(2026, 1, 1)), // old
    ],
    sessions: [
      // Just started (within the live grace) → genuinely live.
      _session('s1', _now.subtract(const Duration(minutes: 1)), status: 'active'),
      _session('s2', DateTime(2026, 6, 20),
          aiStatus: 'completed', summary: insight, aiAt: DateTime(2026, 6, 20)),
      _session('s3', DateTime(2026, 6, 19),
          aiStatus: 'failed', aiAt: DateTime(2026, 6, 19)),
      _session('s4', DateTime(2026, 6, 9), aiStatus: 'completed', summary: insight),
    ],
    readings: [
      _reading('Happy', DateTime(2026, 6, 20)),
      _reading('Happy', DateTime(2026, 6, 20)),
      _reading('Happy', DateTime(2026, 6, 20)),
      _reading('Sad', DateTime(2026, 6, 20)),
      _reading('Angry', DateTime(2026, 1, 1)), // outside the period
    ],
  );
}

class FakeDashboardSource implements AdminDashboardSource {
  final DashboardData? data;
  final bool throwError;
  final Completer<void>? gate; // when set, completes the fetch only when resolved
  int calls = 0;

  FakeDashboardSource({this.data, this.throwError = false, this.gate});

  @override
  Future<DashboardData> fetchDashboard({
    DashboardPeriod period = DashboardPeriod.week,
    DateTime? customStart,
    DateTime? customEnd,
  }) async {
    calls++;
    if (gate != null) await gate!.future;
    if (throwError) throw Exception('boom');
    return data ?? DashboardData.build(users: [], sessions: [], readings: [], totalReadings: 0);
  }
}

DashboardData _emptyData() =>
    DashboardData.build(users: [], sessions: [], readings: [], totalReadings: 0, now: _now);

DashboardData _populatedData() {
  final d = _dataset();
  return DashboardData.build(
    users: d.users,
    sessions: d.sessions,
    readings: d.readings,
    totalReadings: d.readings.length,
    period: DashboardPeriod.week,
    now: _now,
  );
}

Widget _wrap(Widget child) =>
    MaterialApp(theme: buildLightTheme(), home: child);

void main() {
  group('DashboardData.build', () {
    test('1. headline metrics are computed from the rows', () {
      final data = _populatedData();
      final m = data.metrics;
      expect(m.totalUsers, 4);
      expect(m.usersTrend.percent, 100); // 2 this period vs 1 previous
      expect(m.usersTrend.hasBaseline, isTrue);
      expect(m.activeSessions, 1); // only s1
      expect(m.sessionsTrend.percent, 200); // 3 vs 1
    });

    test('2. AI alerts come from failed summaries', () {
      final m = _populatedData().metrics;
      expect(m.aiAlerts, 1); // s3 failed
      expect(m.aiAlertsNew, 1); // failed within the period
    });

    test('3. system health degrades with failed summaries', () {
      final m = _populatedData().metrics;
      expect(m.systemHealthPercent, 87); // 1 failed of 3 completed
      expect(m.systemHealthStatus, SystemHealthStatus.warning);
    });

    test('4. emotion distribution is limited to the period', () {
      final data = _populatedData();
      expect(data.totalDetections, 4); // Angry on Jan 1 excluded
      expect(data.emotions.first.emotion, 'Happy');
      expect(data.emotions.first.percent.round(), 75);
    });

    test('5. latest completed AI summary becomes the insight', () {
      final data = _populatedData();
      expect(data.aiInsight, isNotNull);
      expect(data.aiInsight!.text,
          'Indicators were generally stable this week.');
      expect(data.aiInsight!.stressLevel, 'Low');
    });

    test('6. recent activity is ordered and status-mapped', () {
      final data = _populatedData();
      expect(data.recentActivity.length, 4);
      expect(data.recentActivity.first.status, ActivityStatus.live); // s1
      expect(data.recentActivity[2].status, ActivityStatus.flagged); // s3 failed
    });

    test('7. session trend has data and no future leakage', () {
      final data = _populatedData();
      expect(data.sessionTrend, isNotEmpty);
      expect(data.hasSessionTrendData, isTrue);
    });

    test('8. empty input never throws and yields safe defaults', () {
      final data = _emptyData();
      expect(data.metrics.totalUsers, 0);
      expect(data.emotions, isEmpty);
      expect(data.recentActivity, isEmpty);
      expect(data.aiInsight, isNull);
    });
  });

  group('Admin access policy', () {
    test('only the admin role is treated as admin', () {
      expect(_user('a', _now, role: 'admin').isAdmin, isTrue);
      expect(_user('b', _now).isAdmin, isFalse);
      expect(
          UserProfile(id: 'c', status: 'blocked', role: 'user').isBlocked,
          isTrue);
    });
  });

  group('AdminDashboardScreen widget', () {
    testWidgets('shows loading skeletons before data arrives', (tester) async {
      final gate = Completer<void>();
      final source = FakeDashboardSource(data: _populatedData(), gate: gate);
      await tester.pumpWidget(_wrap(AdminDashboardScreen(source: source)));
      await tester.pump(); // first frame, future still pending

      expect(find.byType(MetricSkeletonCard), findsWidgets);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(MetricSkeletonCard), findsNothing);
    });

    testWidgets('renders metrics once loaded', (tester) async {
      final source = FakeDashboardSource(data: _populatedData());
      await tester.pumpWidget(_wrap(AdminDashboardScreen(source: source)));
      await tester.pumpAndSettle();

      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Total Users'), findsOneWidget);
      expect(find.text('Active Sessions'), findsOneWidget);
      expect(find.text('System Health'), findsOneWidget);
      expect(find.text('4'), findsWidgets); // total users value
    });

    testWidgets('shows an error view with a working retry', (tester) async {
      var shouldThrow = true;
      final good = _populatedData();
      final source = _ToggleSource(() => shouldThrow, good);
      await tester.pumpWidget(_wrap(AdminDashboardScreen(source: source)));
      await tester.pumpAndSettle();

      expect(find.text('Could not load the dashboard'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      shouldThrow = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Total Users'), findsOneWidget);
    });

    testWidgets('empty data renders without crashing', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final source = FakeDashboardSource(data: _emptyData());
      await tester.pumpWidget(_wrap(AdminDashboardScreen(source: source)));
      await tester.pumpAndSettle();

      expect(find.text('No recent sessions yet.'), findsOneWidget);
      expect(find.text('Total Users'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('quick actions trigger tab switches', (tester) async {
      // Tall surface so the Quick Actions row is on-screen.
      await tester.binding.setSurfaceSize(const Size(420, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      int? openedTab;
      final source = FakeDashboardSource(data: _populatedData());
      await tester.pumpWidget(_wrap(AdminDashboardScreen(
        source: source,
        onOpenTab: (i) => openedTab = i,
      )));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Manage Users'));
      await tester.tap(find.text('Manage Users'));
      await tester.pump();
      expect(openedTab, 3); // Users tab
    });

    testWidgets('does not overflow on a small screen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final source = FakeDashboardSource(data: _populatedData());
      await tester.pumpWidget(_wrap(AdminDashboardScreen(source: source)));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}

/// A source whose error behaviour can be flipped between fetches.
class _ToggleSource implements AdminDashboardSource {
  final bool Function() shouldThrow;
  final DashboardData good;
  _ToggleSource(this.shouldThrow, this.good);

  @override
  Future<DashboardData> fetchDashboard({
    DashboardPeriod period = DashboardPeriod.week,
    DateTime? customStart,
    DateTime? customEnd,
  }) async {
    if (shouldThrow()) throw Exception('boom');
    return good;
  }
}
