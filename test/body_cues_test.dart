import 'package:flutter_test/flutter_test.dart';

import 'package:meds_flutter_no_python/models/emotion_result.dart';
import 'package:meds_flutter_no_python/models/sensor_reading.dart';
import 'package:meds_flutter_no_python/services/body_cues.dart';
import 'package:meds_flutter_no_python/services/emotion_fusion.dart';

const _labels = [
  'Angry',
  'Disgust',
  'Fear',
  'Happy',
  'Neutral',
  'Sad',
  'Surprise',
];

final _t0 = DateTime(2026, 1, 1, 12);

const _upright = FaceFrame(
    pitch: 0, yaw: 0, roll: 0, leftEyeOpen: 0.95, rightEyeOpen: 0.95);
const _down = FaceFrame(
    pitch: -25, yaw: 0, roll: 0, leftEyeOpen: 0.9, rightEyeOpen: 0.9);
const _sleepy = FaceFrame(
    pitch: 0, yaw: 0, roll: 0, leftEyeOpen: 0.1, rightEyeOpen: 0.15);

/// Feeds [frames] 1.5 s apart (the live session's capture interval).
BodyCues _feed(List<FaceFrame> frames) {
  final b = BodyCues();
  for (var i = 0; i < frames.length; i++) {
    b.add(frames[i], at: _t0.add(const Duration(milliseconds: 1500) * i));
  }
  return b;
}

/// The head swinging between yaw -15° and +15° every frame: 20 °/s.
BodyCues _restless() => _feed([
      for (var i = 0; i < 6; i++)
        FaceFrame(pitch: 0, yaw: i.isEven ? -15 : 15, roll: 0)
    ]);

ProcessedSensorReading _hr(int v) => ProcessedSensorReading(
      hr: v,
      spo2: 98,
      sensorQuality: 'GOOD',
      hrSource: 'main',
      hrQuality: 'stable',
      rawHr: v,
      algoHr: v,
      instantHr: v,
      sourceHr: v,
      fixedHr: v,
      ir: 100000,
      red: 95000,
    );

EmotionResult _emotion(List<double> probs) {
  var best = 0;
  for (var i = 1; i < probs.length; i++) {
    if (probs[i] > probs[best]) best = i;
  }
  return EmotionResult(
    label: _labels[best],
    confidence: probs[best] * 100,
    probabilities: probs,
  );
}

// Neutral narrowly ahead of Sad; Angry narrowly ahead of Fear.
final _neutralOrSad = _emotion([0.05, 0.05, 0.05, 0.04, 0.40, 0.36, 0.05]);
final _angryOrFear = _emotion([0.34, 0.04, 0.30, 0.04, 0.20, 0.04, 0.04]);

/// One frame through a fresh fusion (the first frame commits its top label).
EmotionResult _fuse(EmotionResult face, int seedBpm, int bpm,
        {BodyCues? body}) =>
    EmotionFusion(seedBaselineBpm: seedBpm)
        .process(face, _labels, _hr(bpm), body: body)
        .emotion;

void main() {
  group('BodyCues', () {
    test('a head held down across the window is a cue', () {
      final b = _feed(List.filled(6, _down));
      expect(b.headDown, isTrue);
      expect(b.insight, contains('head has been down'));
    });

    test('one dip, or too few frames, is not sustained', () {
      expect(_feed([...List.filled(5, _upright), _down]).headDown, isFalse);
      expect(_feed(List.filled(3, _down)).headDown, isFalse); // < minFrames
    });

    test('frames older than the 10 s window drop out', () {
      final b = _feed(List.filled(6, _down))
        ..add(_upright, at: _t0.add(const Duration(seconds: 30)));
      expect(b.headDown, isFalse);
    });

    test('restlessness is mean head speed in degrees per second', () {
      // 5 swings of 30° over 7.5 s.
      final b = _restless();
      expect(b.restlessness, closeTo(20, 1e-9));
      expect(b.restless, isTrue);
      expect(b.insight, 'You seem restless — try a slow breath.');

      // A still head with 1° detector jitter is not restless.
      final still = _feed([
        for (var i = 0; i < 6; i++)
          FaceFrame(pitch: i.isEven ? 0 : 1, yaw: i.isEven ? 0 : 1, roll: 0)
      ]);
      expect(still.restlessness, lessThan(BodyCues.restlessDegPerSec));
      expect(still.restless, isFalse);
    });

    test('eyes closed for a while is fatigue; a blink or a turned head is not',
        () {
      final b = _feed(List.filled(6, _sleepy));
      expect(b.eyesClosing, isTrue);
      expect(b.insight, contains('eyes look tired'));

      const blink = FaceFrame(
          pitch: 0, yaw: 0, roll: 0, leftEyeOpen: 0.05, rightEyeOpen: 0.05);
      expect(_feed([...List.filled(5, _upright), blink]).eyesClosing, isFalse);

      // Eye values are unreliable past 18° of yaw, so they're ignored.
      const turned = FaceFrame(
          pitch: 0, yaw: 30, roll: 0, leftEyeOpen: 0.1, rightEyeOpen: 0.1);
      expect(_feed(List.filled(6, turned)).eyesClosing, isFalse);
    });

    test('frames without pose or eye values raise no cue', () {
      final b = _feed(List.filled(6, const FaceFrame()));
      expect(b.headDown, isFalse);
      expect(b.eyesClosing, isFalse);
      expect(b.restlessness, 0);
      expect(b.insight, isNull);
    });
  });

  group('body-cue fusion nudge', () {
    final headDown = _feed(List.filled(6, _down));

    test('head down + HR below baseline tips Neutral/Sad toward Sad', () {
      expect(_fuse(_neutralOrSad, 80, 70).label, 'Neutral');
      expect(_fuse(_neutralOrSad, 80, 70, body: headDown).label, 'Sad');
    });

    test('head down alone (HR at baseline) changes nothing', () {
      final without = _fuse(_neutralOrSad, 80, 80);
      final withCue = _fuse(_neutralOrSad, 80, 80, body: headDown);
      expect(withCue.label, 'Neutral');
      expect(withCue.probabilities, without.probabilities);
    });

    test('restless + HR above baseline tips Angry/Fear toward Fear', () {
      expect(_fuse(_angryOrFear, 70, 100).label, 'Angry');
      expect(_fuse(_angryOrFear, 70, 100, body: _restless()).label, 'Fear');
      // Restless with a calm HR: no nudge.
      expect(_fuse(_angryOrFear, 70, 70, body: _restless()).label, 'Angry');
    });

    test('the nudge is capped at 10% and never overrides a confident face', () {
      final confident = _emotion([0.02, 0.02, 0.02, 0.02, 0.90, 0.02, 0.00]);
      final without = _fuse(confident, 80, 70);
      final withCue = _fuse(confident, 80, 70, body: headDown);
      expect(withCue.label, 'Neutral');
      expect(withCue.probabilities[5],
          closeTo(0.9 * without.probabilities[5] + 0.1, 1e-9));
      expect(withCue.probabilities.reduce((a, b) => a + b), closeTo(1, 1e-9));
    });
  });
}
