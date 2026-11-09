import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:meds_flutter_no_python/models/emotion_result.dart';
import 'package:meds_flutter_no_python/models/sensor_reading.dart';
import 'package:meds_flutter_no_python/services/emotion_fusion.dart';
import 'package:meds_flutter_no_python/services/voice_classifier.dart';

const _labels = [
  'Angry',
  'Disgust',
  'Fear',
  'Happy',
  'Neutral',
  'Sad',
  'Surprise',
];

// An unsure face (Neutral 40%) with no heart rate, so only voice can move it.
const _face = EmotionResult(
  label: 'Neutral',
  confidence: 40,
  probabilities: [0.10, 0.05, 0.10, 0.15, 0.40, 0.15, 0.05],
);
const _sadVoice = [0.0, 0.0, 0.0, 0.0, 0.1, 0.9, 0.0];

void main() {
  group('voice pre-processing (must match train_voice.py)', () {
    test('trimSilence cuts the same samples as trim() in Python', () {
      // Same signal as the Python reference: a tone between samples 5000 and
      // 21000, very quiet hum elsewhere. Python gives x[4640:21472].
      final x = Float32List(32000);
      for (var i = 0; i < x.length; i++) {
        x[i] = (i >= 5000 && i < 21000)
            ? 0.5 * math.sin(2 * math.pi * 220 * i / 16000)
            : 0.0005 * math.sin(2 * math.pi * 50 * i / 16000);
      }
      final speech = VoiceClassifier.trimSilence(x);
      expect(speech.offsetInBytes ~/ 4, 4640);
      expect(speech.length, 21472 - 4640);
    });

    test('nothing said -> empty', () {
      final hum = Float32List(16000)..fillRange(0, 16000, 0.001);
      expect(
          VoiceClassifier.trimSilence(hum,
              minRms: VoiceClassifier.minSpeechRms),
          isEmpty);
    });

    test('fitToClip repeats the speech to exactly 3 s', () {
      final out = VoiceClassifier.fitToClip(Float32List.fromList([1, 2, 3]));
      expect(out.length, VoiceClassifier.clipSamples);
      expect(out.sublist(0, 6), [1, 2, 3, 1, 2, 3]);
    });

    test('pcm16ToFloat decodes little-endian 16-bit samples', () {
      final bytes = Uint8List(6);
      ByteData.sublistView(bytes)
        ..setInt16(0, 32767, Endian.little)
        ..setInt16(2, -32767, Endian.little)
        ..setInt16(4, 0, Endian.little);
      expect(VoiceClassifier.pcm16ToFloat(bytes), [1.0, -1.0, 0.0]);
    });
  });

  group('voice fusion', () {
    final t0 = DateTime(2026, 1, 1, 12);

    test('a fresh check-in pulls the face toward the voice', () {
      final f = EmotionFusion()..addVoice(_sadVoice, _labels, _labels, at: t0);
      final r = f.process(_face, _labels, ProcessedSensorReading.empty, now: t0);
      // 60% face + 40% voice: Sad = 0.6 * 0.15 + 0.4 * 0.9
      expect(r.emotion.probabilities[5], closeTo(0.45, 1e-9));
    });

    test('the voice fades out after 20 s', () {
      final f = EmotionFusion()..addVoice(_sadVoice, _labels, _labels, at: t0);
      final r = f.process(_face, _labels, ProcessedSensorReading.empty,
          now: t0.add(const Duration(seconds: 30)));
      expect(r.emotion.probabilities[5], closeTo(0.15, 1e-9));
    });

    test('voice labels in another order are matched by name', () {
      final reversed = _labels.reversed.toList();
      final f = EmotionFusion()
        ..addVoice(_sadVoice.reversed.toList(), reversed, _labels, at: t0);
      final r = f.process(_face, _labels, ProcessedSensorReading.empty, now: t0);
      expect(r.emotion.probabilities[5], closeTo(0.45, 1e-9));
    });

    test('mismatch: face looks fine but the voice clearly sounds negative', () {
      const sad = EmotionResult(label: 'Sad', confidence: 70, probabilities: []);
      const unsure =
          EmotionResult(label: 'Sad', confidence: 30, probabilities: []);
      expect(EmotionFusion.voiceMismatch('Happy', sad), 'Sad');
      expect(EmotionFusion.voiceMismatch('Neutral', sad), 'Sad');
      expect(EmotionFusion.voiceMismatch('Sad', sad), isNull); // they agree
      expect(EmotionFusion.voiceMismatch('Happy', unsure), isNull);
    });
  });
}
