import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meds_flutter_no_python/models/ai_insight.dart';
import 'package:meds_flutter_no_python/models/detection_session.dart';
import 'package:meds_flutter_no_python/models/emotion_reading.dart';
import 'package:meds_flutter_no_python/services/ai_service.dart';
import 'package:meds_flutter_no_python/services/insights_service.dart';
import 'package:meds_flutter_no_python/viewmodels/insights_view_model.dart';
import 'package:meds_flutter_no_python/widgets/insights_ai_card.dart';
import 'package:meds_flutter_no_python/widgets/meds_bottom_bar.dart';

final _now = DateTime(2026, 6, 17, 12); // fixed clock (a Wednesday)

class FakeSource implements InsightsSource {
  final List<DetectionSession> sessions;
  final List<EmotionReading> readings;
  FakeSource(this.sessions, this.readings);
  @override
  Future<RawInsights> fetchRaw() async =>
      (sessions: sessions, readings: readings);
}

int _rid = 0;

DetectionSession session(String id, DateTime start, {String status = 'completed'}) =>
    DetectionSession(
      sessionId: id,
      userId: 'u',
      startTime: start,
      endTime: start.add(const Duration(minutes: 5)),
      status: status,
    );

EmotionReading reading(String sid, String emotion, int hr,
        {double confidence = 90, String quality = 'GOOD'}) =>
    EmotionReading(
      id: _rid++,
      createdAt: _now,
      emotion: emotion,
      confidence: confidence,
      hr: hr,
      spo2: 98,
      sensorQuality: quality,
      sessionId: sid,
    );

/// Builds a valid session worth of readings (>=3 confident facial + valid HR).
List<EmotionReading> validReadings(String sid, String emotion, int hr) =>
    List.generate(4, (_) => reading(sid, emotion, hr));

void main() {
  test('1. period filter updates the displayed data', () async {
    final vm = InsightsViewModel(
      source: FakeSource([
        session('a', _now.subtract(const Duration(hours: 2))), // today
        session('b', _now.subtract(const Duration(days: 5))), // earlier this month
      ], [
        ...validReadings('a', 'Happy', 70),
        ...validReadings('b', 'Sad', 90),
      ]),
      clock: () => _now,
    );
    await vm.load();

    vm.setPeriod(InsightsPeriod.today);
    expect(vm.data.validSessions, 1);
    expect(vm.data.dominantEmotion, 'Happy');

    vm.setPeriod(InsightsPeriod.month);
    expect(vm.data.validSessions, 2);
  });

  test('2. invalid sessions are excluded', () async {
    final vm = InsightsViewModel(
      source: FakeSource([
        session('ok', _now.subtract(const Duration(hours: 1))),
        session('notdone', _now.subtract(const Duration(hours: 2)),
            status: 'cancelled'),
        session('lowconf', _now.subtract(const Duration(hours: 3))),
        session('nohr', _now.subtract(const Duration(hours: 4))),
      ], [
        ...validReadings('ok', 'Happy', 72),
        ...validReadings('notdone', 'Happy', 72),
        // low confidence -> not valid facial
        ...List.generate(4, (_) => reading('lowconf', 'Happy', 72, confidence: 10)),
        // disconnected sensor -> no valid HR
        ...List.generate(
            4, (_) => reading('nohr', 'Happy', 0, quality: 'DISCONNECTED')),
      ]),
      clock: () => _now,
    );
    await vm.load();
    vm.setPeriod(InsightsPeriod.today);
    expect(vm.data.validSessions, 1); // only 'ok'
  });

  test('3. average BPM is computed correctly', () async {
    final vm = InsightsViewModel(
      source: FakeSource([
        session('a', _now.subtract(const Duration(hours: 1))),
      ], [
        reading('a', 'Happy', 60),
        reading('a', 'Happy', 80),
        reading('a', 'Happy', 100),
        reading('a', 'Happy', 80),
      ]),
      clock: () => _now,
    );
    await vm.load();
    vm.setPeriod(InsightsPeriod.today);
    expect(vm.data.avgBpm, 80); // (60+80+100+80)/4
  });

  test('4. dominant emotion is computed correctly', () async {
    final vm = InsightsViewModel(
      source: FakeSource([
        session('a', _now.subtract(const Duration(hours: 1))),
      ], [
        reading('a', 'Happy', 70),
        reading('a', 'Happy', 70),
        reading('a', 'Happy', 70),
        reading('a', 'Sad', 70),
      ]),
      clock: () => _now,
    );
    await vm.load();
    vm.setPeriod(InsightsPeriod.today);
    expect(vm.data.dominantEmotion, 'Happy');
    expect(vm.data.dominantPercent, 75);
  });

  test('5. emotion percentages total approximately 100%', () async {
    final vm = InsightsViewModel(
      source: FakeSource([
        session('a', _now.subtract(const Duration(hours: 1))),
      ], [
        ...List.generate(3, (_) => reading('a', 'Happy', 70)),
        ...List.generate(1, (_) => reading('a', 'Neutral', 70)),
      ]),
      clock: () => _now,
    );
    await vm.load();
    vm.setPeriod(InsightsPeriod.today);
    final total = vm.data.distribution.fold<double>(0, (a, s) => a + s.percent);
    expect(total, closeTo(100, 0.5));
  });

  test('6. insight is gated (not enough data) with a single session', () async {
    final vm = InsightsViewModel(
      source: FakeSource([
        session('a', _now.subtract(const Duration(hours: 1))),
      ], [
        ...validReadings('a', 'Happy', 70),
      ]),
      clock: () => _now,
    );
    await vm.load();
    vm.setPeriod(InsightsPeriod.today);
    expect(vm.data.hasData, isTrue);
    expect(vm.data.enoughForInsight, isFalse); // 1 session < min, 1 day < 2
  });

  test('7. empty state when no completed sessions exist', () async {
    final vm = InsightsViewModel(
      source: FakeSource([
        session('x', _now, status: 'cancelled'),
      ], []),
      clock: () => _now,
    );
    await vm.load();
    expect(vm.hasAnyCompletedSession, isFalse);
    expect(vm.data.hasData, isFalse);
  });

  testWidgets('8. retry button re-runs AI generation on failure', (tester) async {
    var calls = 0;
    Future<AiInsight> failing(List<EmotionReading> _) async {
      calls++;
      throw const AiException('AI down');
    }

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: InsightsAiCard(
          enough: true,
          fetchReadings: () async => [reading('a', 'Happy', 70)],
          generate: failing,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(calls, 2);
  });

  testWidgets('9. Insights tab is highlighted in bottom navigation',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        bottomNavigationBar: MedsBottomBar(index: 2, onSelect: (_) {}),
      ),
    ));
    final insights = tester.widget<Text>(find.text('Insights'));
    final home = tester.widget<Text>(find.text('Home'));
    expect(insights.style?.color, medsNavAccent);
    expect(home.style?.color, medsNavMuted);
  });

  test('10. custom date range filters sessions correctly', () async {
    final vm = InsightsViewModel(
      source: FakeSource([
        session('in', DateTime(2026, 5, 10, 10)),
        session('out', DateTime(2026, 6, 10, 10)),
      ], [
        ...validReadings('in', 'Happy', 70),
        ...validReadings('out', 'Happy', 70),
      ]),
      clock: () => _now,
    );
    await vm.load();
    vm.setPeriod(InsightsPeriod.custom,
        start: DateTime(2026, 5, 1), end: DateTime(2026, 5, 31));
    expect(vm.data.validSessions, 1); // only the May session
  });
}
