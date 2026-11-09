import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/emotion_result.dart';

/// Voice-emotion model for the "Are you OK?" check-in.
///
/// The model (training/train_voice.py) takes exactly 3 s of 16 kHz mono audio
/// and does its own log-mel maths, so the app only has to record, cut the
/// silence ([trimSilence]) and repeat the speech up to 3 s ([fitToClip]).
/// Those two mirror trim() / prepare() in train_voice.py — keep them identical,
/// or the model sees different input than it was trained on.
class VoiceClassifier {
  static const int sampleRate = 16000;
  static const int clipSamples = 3 * sampleRate;
  static const int _frame = 512; // N_FFT in train_voice.py
  static const int _hop = 160; // HOP
  static const double _topDb = 30; // TOP_DB

  /// Quieter than this (RMS, full scale = 1.0) is treated as "nothing said".
  /// App-only: training clips always contain speech.
  static const double minSpeechRms = 0.01;

  /// How long the user gets to answer.
  static const Duration answerTime = Duration(seconds: 3);

  Interpreter? _interpreter;
  List<String> _labels = const [];
  AudioRecorder? _recorder; // created on first use: unit tests have no microphone

  bool get isLoaded => _interpreter != null;

  /// Class labels in model-output order, capitalised like the face labels.
  List<String> get labels => _labels;

  Future<void> load() async {
    _interpreter = await Interpreter.fromAsset('assets/voice_model.tflite');
    final raw = await rootBundle.loadString('assets/voice_labels.txt');
    _labels = raw
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .map((e) => e[0].toUpperCase() + e.substring(1).toLowerCase())
        .toList();
  }

  /// Records [answerTime] of microphone audio as 16 kHz mono. Returns null if
  /// the microphone permission is denied.
  Future<Float32List?> record() async {
    final recorder = _recorder ??= AudioRecorder();
    if (!await recorder.hasPermission()) return null;
    final bytes = BytesBuilder(copy: false);
    final stream = await recorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: sampleRate,
      numChannels: 1,
    ));
    final sub = stream.listen(bytes.add);
    await Future<void>.delayed(answerTime);
    await recorder.stop();
    await sub.cancel();
    return pcm16ToFloat(bytes.takeBytes());
  }

  /// Classifies a recorded answer. Returns [EmotionResult.empty] when nothing
  /// loud enough to be speech was recorded.
  EmotionResult classify(Float32List samples) {
    final interp = _interpreter;
    if (interp == null || _labels.isEmpty) return EmotionResult.empty;
    final speech = trimSilence(samples, minRms: minSpeechRms);
    if (speech.isEmpty) return EmotionResult.empty;

    final output = [List<double>.filled(_labels.length, 0.0)];
    interp.run([fitToClip(speech)], output);
    final probs = output.first;
    var best = 0;
    for (var i = 1; i < probs.length; i++) {
      if (probs[i] > probs[best]) best = i;
    }
    return EmotionResult(
      label: _labels[best],
      confidence: probs[best] * 100.0,
      probabilities: probs,
    );
  }

  void close() {
    _interpreter?.close();
    _interpreter = null;
    _recorder?.dispose();
    _recorder = null;
  }

  // ---- Pre-processing (pure, unit-tested against train_voice.py) ------------

  /// Little-endian 16-bit PCM bytes -> samples in [-1, 1].
  static Float32List pcm16ToFloat(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    final out = Float32List(bytes.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = data.getInt16(i * 2, Endian.little) / 32767.0;
    }
    return out;
  }

  /// Cuts leading/trailing silence: keeps from the first to the last frame
  /// whose RMS is within [_topDb] of the loudest frame. Returns an empty list
  /// if even the loudest frame is below [minRms].
  static Float32List trimSilence(Float32List x, {double minRms = 0}) {
    if (x.length < _frame) return x;
    final n = 1 + (x.length - _frame) ~/ _hop;
    final rms = Float64List(n);
    var loudest = 0.0;
    for (var f = 0; f < n; f++) {
      var sum = 0.0;
      final start = f * _hop;
      for (var i = start; i < start + _frame; i++) {
        sum += x[i] * x[i];
      }
      rms[f] = math.sqrt(sum / _frame);
      if (rms[f] > loudest) loudest = rms[f];
    }
    if (loudest < minRms) return Float32List(0);
    final threshold = loudest * math.pow(10, -_topDb / 20);
    var first = 0;
    while (rms[first] < threshold) {
      first++;
    }
    var last = n - 1;
    while (rms[last] < threshold) {
      last--;
    }
    return Float32List.sublistView(x, first * _hop, last * _hop + _frame);
  }

  /// Repeats the trimmed speech until it is exactly [clipSamples] long (no
  /// silent padding — same as prepare(offset=0) in train_voice.py).
  static Float32List fitToClip(Float32List speech) {
    final out = Float32List(clipSamples);
    if (speech.isEmpty) return out;
    for (var i = 0; i < clipSamples; i++) {
      out[i] = speech[i % speech.length];
    }
    return out;
  }
}
