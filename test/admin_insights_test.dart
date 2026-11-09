import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:meds_flutter_no_python/models/admin_insights_model.dart';
import 'package:meds_flutter_no_python/models/ai_insight.dart';
import 'package:meds_flutter_no_python/models/detection_session.dart';
import 'package:meds_flutter_no_python/models/emotion_reading.dart';
import 'package:meds_flutter_no_python/models/user_profile.dart';
import 'package:meds_flutter_no_python/screens/admin/admin_insights_screen.dart';
import 'package:meds_flutter_no_python/services/admin_insights_service.dart';
import 'package:meds_flutter_no_python/theme/app_theme.dart';
import 'package:meds_flutter_no_python/viewmodels/admin_insights_view_model.dart';
import 'package:meds_flutter_no_python/widgets/admin/insight_metric_card.dart';

final _now = DateTime(2026, 6, 21, 14); // Sunday

UserProfile _user(String id, String name) =>
    UserProfile(id: id, name: name, email: '$id@x.com', createdAt: _now);

int _rid = 0;
List<EmotionReading> _readings(
  String sid,
  String emotion,
  int hr,
  int count, {
  DateTime? base,
}) {
  final start = base ?? _now;
  return List.generate(
    count,
    (i) => EmotionReading(
      id: _rid++,
      createdAt: start.add(Duration(seconds: i * 2)),
      emotion: emotion,
      confidence: 90,
      hr: hr,
      spo2: 98,
      sensorQuality: 'GOOD',
      sessionId: sid,
    ),
  );
}

DetectionSession _session(
  String id,
  String userId,
  DateTime start, {
  String aiStatus = 'pending',
  String? aiStress,
}) =>
    DetectionSession(
      sessionId: id,
      userId: userId,
      startTime: start,
      endTime: start.add(const Duration(minutes: 6)),
      status: 'completed',
      aiSummaryStatus: aiStatus,
      aiSummary: aiStress == null
          ? null
          : AiInsight(
              emotionalSummary: 's',
              stressLevel: aiStress,
              trendAnalysis: 't',
              recommendations: const []),
    );

({List<UserProfile> users, List<DetectionSession> sessions, List<EmotionReading> readings})
    _dataset() {
  final sessions = [
    _session('s1', 'u1', DateTime(2026, 6, 19, 10, 23),
        aiStatus: 'completed', aiStress: 'High'),
    _session('s2', 'u2', DateTime(2026, 6, 20, 9, 58),
        aiStatus: 'completed', aiStress: 'Elevated'),
    _session('s3', 'u3', DateTime(2026, 6, 20, 9, 31)),
    _session('s4', 'u2', DateTime(2026, 6, 18, 8)),
  ];
  final readings = <EmotionReading>[
    ..._readings('s1', 'Angry', 90, 4, base: DateTime(2026, 6, 19, 10, 23)),
    ..._readings('s2', 'Sad', 85, 2, base: DateTime(2026, 6, 20, 9, 58)),
    ..._readings('s2', 'Happy', 85, 2, base: DateTime(2026, 6, 20, 10)),
    ..._readings('s3', 'Neutral', 102, 4, base: DateTime(2026, 6, 20, 9, 31)),
    ..._readings('s4', 'Neutral', 80, 4, base: DateTime(2026, 6, 18, 8)),
  ];
  return (
    users: [
      _user('u1', 'Rahul Verma'),
      _user('u2', 'Priya Sharma'),
      _user('u3', 'Aman Singh'),
    ],
    sessions: sessions,
    readings: readings,
  );
}

AdminInsightsData _populated() {
  final d = _dataset();
  return AdminInsightsData.build(
    users: d.users,
    sessions: d.sessions,
    readings: d.readings,
    period: AdminInsightsPeriod.week,
    now: _now,
  );
}

AdminInsightsData _empty() => AdminInsightsData.build(
    users: [], sessions: [], readings: [], now: _now);

class FakeInsightsSource implements AdminInsightsSource {
  final AdminInsightsData data;
  final Completer<void>? gate;
  int calls = 0;

  FakeInsightsSource(this.data, {this.gate});

  @override
  Future<AdminInsightsData> fetchInsights({
    AdminInsightsPeriod period = AdminInsightsPeriod.week,
    DateTime? customStart,
    DateTime? customEnd,
  }) async {
    calls++;
    if (gate != null) await gate!.future;
    return data;
  }
}

Widget _wrap(Widget child) =>
    MaterialApp(theme: buildLightTheme(), home: child);

void main() {
  group('AdminInsightsData.build', () {
    test('1. summary metrics are computed from the rows', () {
      final d = _populated();
      expect(d.avgStress, 38); // mean of 100,50,0,0
      expect(d.avgBpm, 89); // mean of 90,85,102,80
      expect(d.dominantEmotion, 'Neutral');
      expect(d.dominantPercent, 50);
      expect(d.flagged, 2); // s1 High + s2 Elevated
      expect(d.hasData, isTrue);
    });

    test('2. highest stress day is the peak trend bucket', () {
      final d = _populated();
      expect(d.highestStressDay,
          DateFormat('EEEE').format(DateTime(2026, 6, 19)));
      expect(d.trend, isNotEmpty);
    });

    test('3. at-risk users are ranked high-first and filtered', () {
      final d = _populated();
      expect(d.atRiskUsers.length, 3);
      expect(d.atRiskUsers.first.risk, RiskLevel.high);
      expect(d.atRiskUsers.first.name, 'Rahul Verma');
      // Aman's elevated heart rate is surfaced as the indicator.
      final aman = d.atRiskUsers.firstWhere((u) => u.userId == 'u3');
      expect(aman.indicator, 'High Heart Rate');
      expect(aman.risk, RiskLevel.elevated);
    });

    test('4. session performance reflects real ratios', () {
      final p = _populated().performance;
      expect(p.completionRate, 100); // all 4 completed
      expect(p.aiReviewedRate, 50); // 2 of 4 have completed AI summaries
      expect(p.avgDetectionSeconds, isNotNull);
    });

    test('5. empty input never throws and is safe', () {
      final d = _empty();
      expect(d.hasData, isFalse);
      expect(d.avgStress, 0);
      expect(d.atRiskUsers, isEmpty);
      expect(d.emotions, isEmpty);
      expect(d.trend, isEmpty);
      expect(d.dominantEmotion, '—');
    });
  });

  group('AdminInsightsScreen widget', () {
    testWidgets('shows skeletons before data, then metrics', (tester) async {
      final gate = Completer<void>();
      final vm = AdminInsightsViewModel(
          source: FakeInsightsSource(_populated(), gate: gate));
      await tester.pumpWidget(_wrap(AdminInsightsScreen(viewModel: vm)));
      await tester.pump();

      expect(find.byType(InsightMetricSkeleton), findsWidgets);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(InsightMetricSkeleton), findsNothing);
      expect(find.text('Avg Stress Level'), findsOneWidget);
      expect(find.text('Flagged Sessions'), findsOneWidget);
    });

    testWidgets('shows an error view with a working retry', (tester) async {
      final vm = AdminInsightsViewModel(source: _ThrowOnceSource(_populated()));
      await tester.pumpWidget(_wrap(AdminInsightsScreen(viewModel: vm)));
      await tester.pumpAndSettle();

      expect(find.text('Could not load insights'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Avg Stress Level'), findsOneWidget);
    });

    testWidgets('changing the period reloads the data', (tester) async {
      final source = FakeInsightsSource(_populated());
      final vm = AdminInsightsViewModel(source: source);
      await tester.pumpWidget(_wrap(AdminInsightsScreen(viewModel: vm)));
      await tester.pumpAndSettle();
      expect(source.calls, 1);

      await tester.tap(find.text('This Month'));
      await tester.pumpAndSettle();
      expect(vm.period, AdminInsightsPeriod.month);
      expect(source.calls, 2);
    });

    testWidgets('empty data renders without crashing', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 2600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final vm = AdminInsightsViewModel(source: FakeInsightsSource(_empty()));
      await tester.pumpWidget(_wrap(AdminInsightsScreen(viewModel: vm)));
      await tester.pumpAndSettle();

      expect(find.text('No at-risk users in this period.'), findsOneWidget);
      expect(find.text('Avg Stress Level'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('does not overflow on a small screen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final vm = AdminInsightsViewModel(source: FakeInsightsSource(_populated()));
      await tester.pumpWidget(_wrap(AdminInsightsScreen(viewModel: vm)));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}

/// Throws on the first fetch, then succeeds — for the retry test.
class _ThrowOnceSource implements AdminInsightsSource {
  final AdminInsightsData good;
  int calls = 0;
  _ThrowOnceSource(this.good);

  @override
  Future<AdminInsightsData> fetchInsights({
    AdminInsightsPeriod period = AdminInsightsPeriod.week,
    DateTime? customStart,
    DateTime? customEnd,
  }) async {
    calls++;
    if (calls == 1) throw Exception('boom');
    return good;
  }
}
