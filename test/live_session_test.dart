import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meds_flutter_no_python/models/app_notification.dart';
import 'package:meds_flutter_no_python/models/emotion_result.dart';
import 'package:meds_flutter_no_python/models/sensor_reading.dart';
import 'package:meds_flutter_no_python/models/session_aggregates.dart';
import 'package:meds_flutter_no_python/services/live_session_store.dart';
import 'package:meds_flutter_no_python/viewmodels/live_session_controller.dart';
import 'package:meds_flutter_no_python/widgets/meds_bottom_bar.dart';
import 'package:meds_flutter_no_python/widgets/session_control_buttons.dart';

class FakeStore implements LiveSessionStore {
  bool succeed;
  SessionAggregates? saved;
  final List<String> readings = [];
  FakeStore({this.succeed = true});

  @override
  Future<void> saveReading({
    required String sessionId,
    required String emotion,
    required double confidence,
    required int hr,
    required int spo2,
    required String sensorQuality,
  }) async =>
      readings.add(emotion);

  @override
  Future<bool> complete(String sessionId, SessionAggregates aggregates) async {
    saved = aggregates;
    return succeed;
  }
}

ProcessedSensorReading sr(int hr, String quality) => ProcessedSensorReading(
      hr: hr,
      spo2: 98,
      sensorQuality: quality,
      hrSource: 'main',
      hrQuality: 'stable',
      rawHr: hr,
      algoHr: hr,
      instantHr: hr,
      sourceHr: hr,
      fixedHr: hr,
      ir: 1000,
      red: 1000,
    );

EmotionResult er(String label, double confidence) =>
    EmotionResult(label: label, confidence: confidence, probabilities: const [0.9]);

LiveSessionController make({FakeStore? store}) => LiveSessionController(
      cameras: const [],
      sessionId: 'sess-1',
      userId: 'u',
      baselineBpm: 70,
      store: store ?? FakeStore(),
    );

void main() {
  test('1. controller starts in a clean initial state', () {
    final c = make();
    expect(c.loading, isTrue);
    expect(c.elapsed, Duration.zero);
    expect(c.displayBpm, isNull);
  });

  test('2. timer starts, pauses, resumes and stops', () async {
    final c = make()..beginForTest();
    c.tick();
    c.tick();
    expect(c.elapsed.inSeconds, 2);
    c.pause();
    c.tick();
    expect(c.elapsed.inSeconds, 2); // paused → no tick
    c.resume();
    c.tick();
    expect(c.elapsed.inSeconds, 3);
    await c.stop();
    c.tick();
    expect(c.elapsed.inSeconds, 3); // ending → no tick
  });

  test('3. emotion updates from the feed', () {
    final c = make()..beginForTest();
    c.onEmotion(er('Happy', 88), faceVisible: true);
    expect(c.emotion.label, 'Happy');
    expect(c.emotion.confidence, 88);
  });

  test('4. BPM updates from a valid sensor reading', () {
    final c = make()..beginForTest();
    c.onSensor(sr(78, 'GOOD'));
    expect(c.displayBpm, 78);
    expect(c.hrHistory.last, 78);
  });

  test('5. invalid sensor readings are not shown as valid BPM', () {
    final c = make()..beginForTest();
    c.onSensor(sr(0, 'DISCONNECTED'));
    expect(c.displayBpm, isNull);
    c.onSensor(sr(80, 'NO FINGER'));
    expect(c.displayBpm, isNull); // NO FINGER isn't a valid quality
  });

  test('6. repeated low-signal warnings are debounced', () {
    final c = make()..beginForTest();
    c.onSensor(sr(0, 'BAD SIGNAL'));
    expect(c.alerts.currentAlert?.type, NotificationType.lowSensorQuality);
    expect(c.alerts.shouldEmit(NotificationType.lowSensorQuality), isTrue);
    expect(c.alerts.shouldEmit(NotificationType.lowSensorQuality), isFalse);
  });

  testWidgets('7. Stop button triggers its callback', (tester) async {
    var stopped = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SessionControlButtons(
          paused: false,
          onPauseResume: () {},
          onStop: () => stopped = true,
        ),
      ),
    ));
    await tester.tap(find.text('Stop Session'));
    expect(stopped, isTrue);
  });

  test('8. successful stop saves the correct aggregates', () async {
    final store = FakeStore();
    final c = make(store: store)..beginForTest();
    c.onEmotion(er('Happy', 88), faceVisible: true);
    c.onEmotion(er('Happy', 90), faceVisible: true);
    c.onEmotion(er('Sad', 60), faceVisible: true);
    c.onSensor(sr(80, 'GOOD'));
    c.onSensor(sr(90, 'GOOD'));

    final ok = await c.stop();
    expect(ok, isTrue);
    expect(store.saved!.dominantEmotion, 'Happy');
    expect(store.saved!.averageBpm, 85);
    expect(store.saved!.minimumBpm, 80);
    expect(store.saved!.maximumBpm, 90);
    expect(store.saved!.baselineBpm, 70);
  });

  test('9. failed save returns false', () async {
    final c = make(store: FakeStore(succeed: false))..beginForTest();
    expect(await c.stop(), isFalse);
  });

  testWidgets('10. bottom navigation shows the Live flow active', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        bottomNavigationBar: MedsBottomBar(index: -1, onSelect: (_) {}),
      ),
    ));
    for (final label in ['Home', 'History', 'Insights', 'Profile']) {
      final t = tester.widget<Text>(find.text(label));
      expect(t.style?.color, medsNavMuted);
    }
  });

  test('11. camera-only session runs + saves without any sensor data', () async {
    final store = FakeStore();
    final c = LiveSessionController(
      cameras: const [],
      sessionId: 'sess-1',
      useSensor: false,
      store: store,
    )..beginForTest();
    c.onEmotion(er('Happy', 88), faceVisible: true);
    expect(c.displayBpm, isNull);
    expect(c.liveInsight, 'Emotion readings are currently stable.');

    final ok = await c.stop();
    expect(ok, isTrue);
    expect(store.saved!.dominantEmotion, 'Happy');
    expect(store.saved!.averageBpm, 0); // no sensor → no BPM
  });
}
