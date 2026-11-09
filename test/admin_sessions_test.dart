import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meds_flutter_no_python/models/admin_sessions_model.dart';
import 'package:meds_flutter_no_python/models/detection_session.dart';
import 'package:meds_flutter_no_python/models/emotion_reading.dart';
import 'package:meds_flutter_no_python/models/user_profile.dart';
import 'package:meds_flutter_no_python/screens/admin/admin_sessions_screen.dart';
import 'package:meds_flutter_no_python/services/admin_sessions_service.dart';
import 'package:meds_flutter_no_python/theme/app_theme.dart';
import 'package:meds_flutter_no_python/widgets/admin/dashboard_metric_card.dart';

final _now = DateTime(2026, 6, 21, 14);

UserProfile _u(String id, String name) =>
    UserProfile(id: id, name: name, email: '$id@example.com');

int _rid = 0;
List<EmotionReading> _readings(String sid, String emotion, int hr, int n,
        {DateTime? at}) =>
    List.generate(
      n,
      (i) => EmotionReading(
        id: _rid++,
        createdAt: at ?? _now,
        emotion: emotion,
        confidence: 90,
        hr: hr,
        spo2: 98,
        sensorQuality: 'GOOD',
        sessionId: sid,
      ),
    );

DetectionSession _s(String id, String uid, DateTime start,
        {String status = 'completed', String aiStatus = 'completed'}) =>
    DetectionSession(
      sessionId: id,
      userId: uid,
      startTime: start,
      endTime: status == 'active' ? null : start.add(const Duration(minutes: 20)),
      status: status,
      aiSummaryStatus: aiStatus,
    );

MonitorSessionsData _populated() {
  final users = [
    _u('u1', 'Amirul Hakim'),
    _u('u2', 'Nur Aisyah'),
    _u('u3', 'Hakimi Daniel'),
  ];
  final sessions = [
    _s('s1', 'u1', DateTime(2026, 6, 21, 10, 32), status: 'active'),
    _s('s2', 'u2', DateTime(2026, 6, 20, 9, 45)),
    _s('s3', 'u3', DateTime(2026, 6, 20, 9, 10), aiStatus: 'failed'),
    _s('s4', 'u2', DateTime(2026, 6, 19, 8, 30), aiStatus: 'pending'),
  ];
  final readings = [
    ..._readings('s1', 'Happy', 78, 3),
    ..._readings('s2', 'Neutral', 72, 4),
    ..._readings('s3', 'Angry', 102, 4),
    ..._readings('s4', 'Sad', 64, 4),
  ];
  return MonitorSessionsData.build(
      users: users, sessions: sessions, readings: readings, now: _now);
}

class FakeSessionsSource implements AdminSessionsSource {
  final MonitorSessionsData? data;
  final bool throwError;
  final Completer<void>? gate;
  FakeSessionsSource({this.data, this.throwError = false, this.gate});

  @override
  Future<MonitorSessionsData> fetchSessions() async {
    if (gate != null) await gate!.future;
    if (throwError) throw Exception('boom');
    return data ?? MonitorSessionsData.empty;
  }
}

Widget _wrap(Widget child) =>
    MaterialApp(theme: buildLightTheme(), home: child);

void main() {
  group('MonitorSessionsData.build', () {
    test('classifies sessions and enriches rows', () {
      final d = _populated();
      expect(d.total, 4);
      expect(d.live, 1); // s1 active
      expect(d.completed, 1); // s2
      expect(d.flagged, 1); // s3 failed AI
      // Newest first; s1 is the live one with its emotion + HR.
      final first = d.sessions.first;
      expect(first.userName, 'Amirul Hakim');
      expect(first.status, ActivityStatus.live);
      expect(first.emotion, 'Happy');
      expect(first.avgBpm, 78);
      expect(d.flaggedDelta, 1); // 1 this week, 0 the week before
    });

    test('an abandoned active session is not shown as Live', () {
      // Session left "active" because the app was closed without ending it: its
      // last reading is hours old, so monitoring has clearly stopped.
      final start = _now.subtract(const Duration(hours: 6));
      final d = MonitorSessionsData.build(
        users: [_u('u1', 'Stale User')],
        sessions: [_s('s1', 'u1', start, status: 'active')],
        readings: _readings('s1', 'Happy', 78, 3,
            at: start.add(const Duration(minutes: 8))),
        now: _now,
      );
      expect(d.live, 0); // not counted as live
      expect(d.completed, 1); // treated as ended instead
      final row = d.sessions.first;
      expect(row.status, ActivityStatus.completed);
      // Duration is the measured span (start → last reading), not "now − start".
      expect(row.duration, const Duration(minutes: 8));
    });

    test('empty input is safe', () {
      final d = MonitorSessionsData.build(
          users: [], sessions: [], readings: [], now: _now);
      expect(d.total, 0);
      expect(d.sessions, isEmpty);
      expect(d.flaggedDelta, 0);
    });
  });

  group('AdminSessionsScreen widget', () {
    testWidgets('shows a loader then the list', (tester) async {
      final gate = Completer<void>();
      final source = FakeSessionsSource(data: _populated(), gate: gate);
      await tester.pumpWidget(_wrap(AdminSessionsScreen(source: source)));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Monitor Sessions'), findsOneWidget);
      expect(find.text('Amirul Hakim'), findsOneWidget);
      expect(find.text('Total Sessions'), findsWidgets);
      expect(find.text('All (4)'), findsOneWidget);
    });

    testWidgets('tab filter narrows the list', (tester) async {
      final source = FakeSessionsSource(data: _populated());
      await tester.pumpWidget(_wrap(AdminSessionsScreen(source: source)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Flagged (1)'));
      await tester.pumpAndSettle();

      expect(find.text('Hakimi Daniel'), findsOneWidget); // flagged user
      expect(find.text('Amirul Hakim'), findsNothing); // live user hidden
    });

    testWidgets('search filters by name', (tester) async {
      final source = FakeSessionsSource(data: _populated());
      await tester.pumpWidget(_wrap(AdminSessionsScreen(source: source)));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'amirul');
      await tester.pumpAndSettle();

      expect(find.text('Amirul Hakim'), findsOneWidget);
      expect(find.text('Hakimi Daniel'), findsNothing);
    });

    testWidgets('error state shows Try Again', (tester) async {
      final source = FakeSessionsSource(throwError: true);
      await tester.pumpWidget(_wrap(AdminSessionsScreen(source: source)));
      await tester.pumpAndSettle();

      expect(find.text('Failed to load sessions'), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);
    });

    testWidgets('does not overflow on a small screen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final source = FakeSessionsSource(data: _populated());
      await tester.pumpWidget(_wrap(AdminSessionsScreen(source: source)));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Sanity: the reused metric card is present.
      expect(find.byType(DashboardMetricCard), findsWidgets);
    });
  });
}
