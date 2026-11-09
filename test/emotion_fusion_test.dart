import 'package:flutter_test/flutter_test.dart';

import 'package:meds_flutter_no_python/models/emotion_result.dart';
import 'package:meds_flutter_no_python/models/multimodal_result.dart';
import 'package:meds_flutter_no_python/models/sensor_reading.dart';
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

EmotionResult _neutral() => const EmotionResult(
      label: 'Neutral',
      confidence: 80,
      probabilities: [0.02, 0.02, 0.02, 0.05, 0.80, 0.05, 0.04],
    );

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

MultimodalResult _feed(EmotionFusion f, int bpm, {int times = 1}) {
  late MultimodalResult r;
  for (var i = 0; i < times; i++) {
    r = f.process(_neutral(), _labels, _hr(bpm));
  }
  return r;
}

/// A sensor reading with an explicit quality (drives HR reliability).
ProcessedSensorReading _hrq(int v, String quality) => ProcessedSensorReading(
      hr: v,
      spo2: 98,
      sensorQuality: quality,
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

/// Builds an [EmotionResult] from a probability vector (top class = label).
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

// Confident single-emotion frames.
final _happy = _emotion([0.02, 0.02, 0.02, 0.85, 0.05, 0.02, 0.02]);
final _sad = _emotion([0.02, 0.03, 0.03, 0.05, 0.03, 0.82, 0.02]);

MultimodalResult _feedEmotion(
  EmotionFusion f,
  EmotionResult e,
  ProcessedSensorReading s,
  int times,
) {
  late MultimodalResult r;
  for (var i = 0; i < times; i++) {
    r = f.process(e, _labels, s);
  }
  return r;
}

void main() {
  test('seeded baseline is ready from the first frame', () {
    final f = EmotionFusion(seedBaselineBpm: 80);
    final r = f.process(_neutral(), _labels, _hr(80));
    expect(r.baselineReady, isTrue);
    expect(r.baselineBpm, 80);
    expect(r.arousal, Arousal.normal); // delta 0
  });

  test('baseline adapts DOWN toward the sustained resting floor', () {
    final f = EmotionFusion(seedBaselineBpm: 90);
    _feed(f, 70, times: 12); // user settles to a calm 70
    expect(f.baselineHr, 70); // ratcheted 90 → 70

    // 78 is now "elevated" vs the corrected 70 baseline (it was "low" vs 90).
    final r = f.process(_neutral(), _labels, _hr(78));
    expect(r.arousal, Arousal.elevated);
  });

  test('baseline never rises when HR climbs (stress cannot inflate it)', () {
    final f = EmotionFusion(seedBaselineBpm: 70);
    final r = _feed(f, 100, times: 12); // user active the whole time
    expect(f.baselineHr, 70); // stays put
    expect(r.arousal, Arousal.high); // 100 vs 70 = high arousal
  });

  test('without a seed, a warm-up median establishes the baseline', () {
    final f = EmotionFusion();
    for (var i = 0; i < 7; i++) {
      final r = f.process(_neutral(), _labels, _hr(72));
      expect(r.baselineReady, isFalse); // not enough samples yet
    }
    final r = f.process(_neutral(), _labels, _hr(72)); // 8th sample
    expect(r.baselineReady, isTrue);
    expect(f.baselineHr, 72);
  });

  test('hysteresis: one off-frame does not flip the label; a sustained change does',
      () {
    final f = EmotionFusion(seedBaselineBpm: 75);
    final calm = _hrq(75, 'GOOD'); // arousal normal → HR does not reweight

    // Commit Happy over several frames.
    var r = _feedEmotion(f, _happy, calm, 5);
    expect(r.emotion.label, 'Happy');

    // A single Sad frame is absorbed by smoothing + hysteresis.
    r = f.process(_sad, _labels, calm);
    expect(r.emotion.label, 'Happy');

    // A sustained Sad run eventually commits.
    r = _feedEmotion(f, _sad, calm, 6);
    expect(r.emotion.label, 'Sad');
  });

  test('reliability gating: a bad-signal HR cannot invent arousal', () {
    final good = EmotionFusion(seedBaselineBpm: 70);
    expect(good.process(_neutral(), _labels, _hrq(100, 'GOOD')).arousal,
        Arousal.high);

    final bad = EmotionFusion(seedBaselineBpm: 70);
    final r = bad.process(_neutral(), _labels, _hrq(100, 'BAD SIGNAL'));
    expect(r.arousal, Arousal.normal); // HR ignored → no arousal
  });

  test('HR corroborates an ambiguous face but never overrides a confident one',
      () {
    final aroused = _hrq(100, 'GOOD'); // high arousal vs a 70 baseline

    // Near-tie between Neutral (0.40) and Angry (0.35): HR breaks it toward
    // the high-arousal class.
    final ambiguous = EmotionFusion(seedBaselineBpm: 70);
    final r1 = ambiguous.process(
        _emotion([0.35, 0.05, 0.05, 0.05, 0.40, 0.05, 0.05]), _labels, aroused);
    expect(r1.arousal, Arousal.high);
    expect(r1.emotion.label, 'Angry');

    // A confident Neutral (0.90) is left alone despite the same high arousal.
    final confident = EmotionFusion(seedBaselineBpm: 70);
    final r2 = confident.process(
        _emotion([0.02, 0.02, 0.02, 0.02, 0.90, 0.02, 0.00]), _labels, aroused);
    expect(r2.emotion.label, 'Neutral');
  });
}
