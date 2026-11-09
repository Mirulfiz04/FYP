import 'package:flutter_test/flutter_test.dart';

import 'package:meds_flutter_no_python/models/detection_session.dart';
import 'package:meds_flutter_no_python/models/emotion_reading.dart';
import 'package:meds_flutter_no_python/models/session_analytics.dart';
import 'package:meds_flutter_no_python/services/session_details_service.dart';
import 'package:meds_flutter_no_python/viewmodels/session_details_controller.dart';

int _id = 0;
final _base = DateTime(2026, 6, 22, 11, 44, 57);

EmotionReading rd({
  int sec = 0,
  String emotion = 'Happy',
  double conf = 80,
  int hr = 0,
  int spo2 = 0,
  String quality = 'GOOD',
}) =>
    EmotionReading(
      id: _id++,
      createdAt: _base.add(Duration(seconds: sec)),
      emotion: emotion,
      confidence: conf,
      hr: hr,
      spo2: spo2,
      sensorQuality: quality,
      sessionId: 'SES-1',
    );

DetectionSession session({String aiStatus = 'completed'}) => DetectionSession(
      sessionId: 'SES-1',
      userId: 'u1',
      startTime: _base,
      endTime: _base.add(const Duration(minutes: 1, seconds: 8)),
      status: 'completed',
      aiSummaryStatus: aiStatus,
    );

class FakeService implements SessionDetailsService {
  final List<EmotionReading> readings;
  final bool fail;
  bool reviewFlag = false;
  bool deleted = false;
  FakeService(this.readings, {this.fail = false});

  @override
  Future<SessionDetailsData> load(String sessionId) async {
    if (fail) throw Exception('boom');
    return SessionDetailsData(
      session: session(),
      readings: readings,
      analytics: SessionAnalytics.from(readings),
      userName: 'Alex Johnson',
      viewerIsAdmin: false,
      isOwner: true,
    );
  }

  @override
  Future<DetectionSession> reloadSession(String sessionId) async => session();

  @override
  Future<bool> setReview(String sessionId, bool flagged) async {
    reviewFlag = flagged;
    return true;
  }

  @override
  Future<bool> delete(String sessionId) async {
    deleted = true;
    return true;
  }
}

/// Starts "processing" and flips to "completed" after [readyAfter] reloads, to
/// exercise the AI-summary polling.
class PollingFakeService implements SessionDetailsService {
  final int readyAfter;
  int reloadCalls = 0;
  PollingFakeService({this.readyAfter = 2});

  @override
  Future<SessionDetailsData> load(String sessionId) async => SessionDetailsData(
        session: session(aiStatus: 'processing'),
        readings: const [],
        analytics: SessionAnalytics.from(const []),
        userName: 'Alex',
        viewerIsAdmin: false,
        isOwner: true,
      );

  @override
  Future<DetectionSession> reloadSession(String sessionId) async {
    reloadCalls++;
    return session(
        aiStatus: reloadCalls >= readyAfter ? 'completed' : 'processing');
  }

  @override
  Future<bool> setReview(String sessionId, bool flagged) async => true;

  @override
  Future<bool> delete(String sessionId) async => true;
}

void main() {
  test('1. empty readings → empty/limited analytics', () {
    final a = SessionAnalytics.from([]);
    expect(a.hasReadings, isFalse);
    expect(a.avgBpm, isNull);
    expect(a.reliability, 'Limited');
  });

  test('2. avg/min/max use valid HR readings only', () {
    final a = SessionAnalytics.from([
      rd(sec: 0, hr: 60, quality: 'GOOD'),
      rd(sec: 1, hr: 80, quality: 'GOOD'),
      rd(sec: 2, hr: 100, quality: 'HOLDING HR'),
      rd(sec: 3, hr: 0, quality: 'NO FINGER'), // invalid
      rd(sec: 4, hr: 90, quality: 'BAD SIGNAL'), // invalid quality
    ]);
    expect(a.validHrCount, 3);
    expect(a.invalidReadings, 2);
    expect(a.avgBpm, 80); // (60+80+100)/3
    expect(a.minBpm, 60);
    expect(a.maxBpm, 100);
  });

  test('3. invalid BPM is never treated as a valid reading', () {
    final a = SessionAnalytics.from([
      rd(hr: 0, quality: 'GOOD'),
      rd(hr: 0, quality: 'DISCONNECTED'),
    ]);
    expect(a.hasValidHr, isFalse);
    expect(a.avgBpm, isNull);
  });

  test('4. dominant emotion + percentage', () {
    final a = SessionAnalytics.from([
      rd(emotion: 'Happy'),
      rd(emotion: 'Happy'),
      rd(emotion: 'Happy'),
      rd(emotion: 'Sad'),
      rd(emotion: 'Neutral'),
    ]);
    expect(a.dominantEmotion, 'Happy');
    expect(a.dominantCount, 3);
    expect(a.dominantPercent, 60);
  });

  test('5. emotion percentages total ~100%', () {
    final a = SessionAnalytics.from([
      rd(emotion: 'Happy'),
      rd(emotion: 'Neutral'),
      rd(emotion: 'Sad'),
    ]);
    final total = a.distribution.fold<double>(0, (s, e) => s + e.percent);
    expect(total, closeTo(100, 0.5));
  });

  test('6. recent = latest five, newest first', () {
    final a = SessionAnalytics.from(
        List.generate(7, (i) => rd(sec: i, emotion: 'Neutral')));
    expect(a.recent.length, 5);
    expect(a.recent.first.createdAt, _base.add(const Duration(seconds: 6)));
  });

  test('7. stress indicator reflects the emotion mix', () {
    final calm = SessionAnalytics.from(
        List.generate(4, (_) => rd(emotion: 'Happy')));
    expect(calm.stressIndicator, 'Low');
    final tense = SessionAnalytics.from(
        List.generate(4, (_) => rd(emotion: 'Sad')));
    expect(tense.stressIndicator, 'Elevated');
  });

  test('8. reliability rules', () {
    final good = SessionAnalytics.from([
      for (var i = 0; i < 8; i++) rd(sec: i, hr: 70 + i, conf: 70),
    ]);
    expect(good.reliability, 'Good');
    final limited = SessionAnalytics.from([rd(hr: 70), rd(hr: 0)]);
    expect(limited.reliability, 'Limited');
  });

  test('9. controller loads via the service, surfaces errors', () async {
    final c = SessionDetailsController(
        service: FakeService([rd(hr: 72)]), sessionId: 'SES-1');
    await c.load();
    expect(c.data, isNotNull);
    expect(c.data!.analytics.validHrCount, 1);

    final err = SessionDetailsController(
        service: FakeService([], fail: true), sessionId: 'SES-1');
    await err.load();
    expect(err.error, isNotNull);
    expect(err.data, isNull);
  });

  test('10. report text includes key session fields', () async {
    final c = SessionDetailsController(
        service: FakeService([rd(emotion: 'Happy', hr: 72)]),
        sessionId: 'SES-1');
    await c.load();
    final report = c.reportText();
    expect(report, contains('Session ID: SES-1'));
    expect(report, contains('Dominant emotion: Happy'));
    expect(report, contains('not a medical diagnosis'));
  });

  test('11. AI summary polling refreshes when it becomes ready', () async {
    final c = SessionDetailsController(
      service: PollingFakeService(readyAfter: 2),
      sessionId: 'SES-1',
      aiPollInterval: const Duration(milliseconds: 10),
    );
    await c.load();
    expect(c.aiPending, isTrue); // still "processing" on first load
    await Future.delayed(const Duration(milliseconds: 80));
    expect(c.data!.session.aiSummaryStatus, 'completed');
    expect(c.aiPending, isFalse);
    c.dispose();
  });
}
