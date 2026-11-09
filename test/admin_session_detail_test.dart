import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meds_flutter_no_python/models/admin_session_detail.dart';
import 'package:meds_flutter_no_python/models/ai_insight.dart';
import 'package:meds_flutter_no_python/models/detection_session.dart';
import 'package:meds_flutter_no_python/models/emotion_reading.dart';
import 'package:meds_flutter_no_python/screens/admin/admin_session_detail_screen.dart';
import 'package:meds_flutter_no_python/theme/app_theme.dart';
import 'package:meds_flutter_no_python/widgets/admin/hr_trend_chart.dart';

final _start = DateTime(2026, 6, 20, 10, 0);

const _aiText =
    'The user maintained a stable heart rate and mostly positive emotional '
    'patterns during this session. No abnormal stress indicators were detected.';

DetectionSession _session({String aiStatus = 'completed', bool withAi = true}) =>
    DetectionSession(
      sessionId: 'sess-1',
      userId: 'u1',
      startTime: _start,
      endTime: _start.add(const Duration(minutes: 28)),
      status: 'completed',
      aiSummaryStatus: aiStatus,
      aiSummary: withAi
          ? const AiInsight(
              emotionalSummary: _aiText,
              stressLevel: 'Low',
              trendAnalysis: 'steady',
              recommendations: [])
          : null,
    );

int _rid = 0;
List<EmotionReading> _readings() {
  const hrs = [70, 75, 80, 102, 90, 78, 76, 80, 82, 79, 77, 72];
  const emotions = [
    'Happy', 'Happy', 'Happy', // Q1
    'Neutral', 'Neutral', 'Neutral', // Q2
    'Happy', 'Happy', 'Happy', // Q3
    'Happy', 'Happy', 'Happy', // Q4
  ];
  return [
    for (var i = 0; i < hrs.length; i++)
      EmotionReading(
        id: _rid++,
        createdAt: _start.add(Duration(minutes: i * 2)),
        emotion: emotions[i],
        confidence: 90,
        hr: hrs[i],
        spo2: 98,
        sensorQuality: 'GOOD',
        sessionId: 'sess-1',
      ),
  ];
}

Widget _wrap(Widget child) =>
    MaterialApp(theme: buildLightTheme(), home: child);

void main() {
  group('SessionDetailData.build', () {
    test('computes session analytics', () {
      final d = SessionDetailData.build(
          session: _session(), readings: _readings());
      expect(d.avgBpm, 80);
      expect(d.peakBpm, 102);
      expect(d.dominantEmotion, 'Happy');
      expect(d.sensorQuality, 'Good');
      expect(d.hrTrend.length, 12);
      expect(d.finalState, 'Calm');
      // Happy → Neutral → Happy collapses to three segments.
      expect(d.emotionTimeline.length, 3);
      expect(d.aiSummary, _aiText);
    });

    test('empty readings are safe', () {
      final d = SessionDetailData.build(
          session: _session(withAi: false), readings: []);
      expect(d.avgBpm, 0);
      expect(d.peakBpm, 0);
      expect(d.dominantEmotion, '—');
      expect(d.emotionTimeline, isEmpty);
      expect(d.aiSummary, isNull);
    });
  });

  group('AdminSessionDetailScreen widget', () {
    Widget screen({
      Future<List<EmotionReading>> Function(String)? loader,
    }) =>
        _wrap(AdminSessionDetailScreen(
          session: _session(),
          userName: 'Amirul Hakim',
          readingsLoader: loader ?? (_) async => _readings(),
        ));

    testWidgets('renders all sections', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();

      expect(find.text('Session Details'), findsOneWidget);
      expect(find.text('Amirul Hakim'), findsWidgets);
      expect(find.text('Heart Rate Trend'), findsOneWidget);
      expect(find.byType(HrTrendChart), findsOneWidget);
      expect(find.text('Emotion Timeline'), findsOneWidget);
      expect(find.text('Session Overview'), findsOneWidget);
      expect(find.text('AI Session Summary'), findsOneWidget);
      expect(find.textContaining('stable heart rate'), findsOneWidget);
      expect(find.text('Flags & Review'), findsOneWidget);
      expect(find.text('Export Report'), findsOneWidget);
    });

    testWidgets('shows a loader before readings arrive', (tester) async {
      final gate = Completer<List<EmotionReading>>();
      await tester.pumpWidget(screen(loader: (_) => gate.future));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      gate.complete(_readings());
      await tester.pumpAndSettle();
      expect(find.byType(HrTrendChart), findsOneWidget);
    });

    testWidgets('error state shows Try Again', (tester) async {
      await tester.pumpWidget(
          screen(loader: (_) async => throw Exception('boom')));
      await tester.pumpAndSettle();

      expect(find.text('Could not load session'), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);
    });

    testWidgets('does not overflow on a small screen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
