import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as imglib;
import 'package:tflite_flutter/tflite_flutter.dart';
import '../models/emotion_result.dart';

class EmotionClassifier {
  static const int inputSize = 224;

  late final Interpreter _interpreter;
  late final List<String> _labels;
  bool _loaded = false;

  bool get isLoaded => _loaded;

  Future<void> load() async {
    _interpreter = await Interpreter.fromAsset('assets/model.tflite');
    final rawLabels = await rootBundle.loadString('assets/labels.txt');
    _labels = rawLabels
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .map(_cleanLabel)
        .toList();

    // Debug: print tensor info
    final inputTensor  = _interpreter.getInputTensor(0);
    final outputTensor = _interpreter.getOutputTensor(0);
    debugPrint('✅ Model loaded. Labels (${_labels.length}): $_labels');
    debugPrint('📥 Input  tensor shape: ${inputTensor.shape}  type: ${inputTensor.type}');
    debugPrint('📤 Output tensor shape: ${outputTensor.shape} type: ${outputTensor.type}');

    _loaded = true;
  }

  String _cleanLabel(String value) {
    final parts = value.split(' ');
    var label = value;
    if (parts.length >= 2 && int.tryParse(parts.first) != null) {
      label = parts.sublist(1).join(' ');
    }
    label = label.trim();
    if (label.toLowerCase() == 'suprise') return 'Surprise';
    if (label.isEmpty) return 'Unknown';
    return label[0].toUpperCase() + label.substring(1).toLowerCase();
  }

  /// Turn raw model output into a valid probability distribution.
  ///
  /// The Teachable Machine model already ends in softmax, so its output sums
  /// to ~1. But this guards against NaN/Inf and, if the model ever returns
  /// raw logits (negative / >1 values), falls back to a softmax instead of
  /// naively clipping — which would otherwise flatten every class to 1/N.
  List<double> _toProbabilities(List<double> raw) {
    final arr = raw.map((e) => e.isFinite ? e : 0.0).toList();
    if (arr.isEmpty) return arr;

    final total = arr.fold<double>(0.0, (a, b) => a + b);
    final maxVal = arr.reduce((a, b) => a > b ? a : b);
    final allNonNeg = arr.every((e) => e >= 0);

    // Already looks like softmax/sigmoid output.
    if (allNonNeg && total > 0 && maxVal <= 1.0) {
      return arr.map((e) => e / total).toList();
    }

    // Otherwise treat as logits → softmax (numerically stable).
    final exps = arr.map((e) => _expSafe(e - maxVal)).toList();
    final expTotal = exps.fold<double>(0.0, (a, b) => a + b);
    if (expTotal <= 0) {
      final uniform = 1.0 / arr.length;
      return List<double>.filled(arr.length, uniform);
    }
    return exps.map((e) => e / expTotal).toList();
  }

  double _expSafe(double x) {
    final v = math.exp(x);
    return v.isFinite ? v : 0.0;
  }

  Future<EmotionResult> classifyImageFile(String imagePath) async {
    if (!_loaded) return EmotionResult.empty;

    final bytes = await File(imagePath).readAsBytes();
    // The camera saves JPEG, so try the JPEG decoder directly first (faster and
    // avoids any format-detection edge cases), then fall back to auto-detect.
    var decoded = imglib.decodeJpg(bytes);
    decoded ??= imglib.decodeImage(bytes);
    if (decoded == null) {
      debugPrint('⚠️ Could not decode image (${bytes.length} bytes): $imagePath');
      return EmotionResult.empty;
    }

    final image   = imglib.bakeOrientation(decoded);
    final resized = imglib.copyResizeCropSquare(image, size: inputSize);

    // Build input [1, 224, 224, 3] normalised to [-1, 1].
    // IMPORTANT: This model is a Teachable Machine export. Those models expect
    // RGB normalised to [-1, 1] ((pixel / 127.5) - 1.0), NOT [0, 1]. Using
    // [0, 1] here gave weak / wrong predictions (e.g. Neutral read as Sad).
    final input = List.generate(
      1,
      (_) => List.generate(
        inputSize,
        (y) => List.generate(
          inputSize,
          (x) {
            final pixel = resized.getPixel(x, y);
            return [
              pixel.r / 127.5 - 1.0,
              pixel.g / 127.5 - 1.0,
              pixel.b / 127.5 - 1.0,
            ];
          },
        ),
      ),
    );

    // Output shape from model (e.g. [1, 7])
    final outputShape = _interpreter.getOutputTensor(0).shape;
    final outputSize  = outputShape.last;           // use actual model output size
    final output      = [List<double>.filled(outputSize, 0.0)];

    try {
      _interpreter.run(input, output);
    } catch (e) {
      debugPrint('⚠️ interpreter.run error: $e');
      return EmotionResult.empty;
    }

    final probs = _toProbabilities(output.first);
    debugPrint('🧠 Raw probs: $probs');   // ← will appear in VS Code debug console

    if (probs.isEmpty) return EmotionResult.empty;

    var bestIndex = 0;
    var bestValue = probs[0];
    for (var i = 1; i < probs.length; i++) {
      if (probs[i] > bestValue) {
        bestIndex = i;
        bestValue = probs[i];
      }
    }

    // Map index → label (pad/trim if sizes differ)
    final label = bestIndex < _labels.length ? _labels[bestIndex] : 'Unknown';
    debugPrint('🎭 Emotion: $label  (${(bestValue * 100).toStringAsFixed(1)}%)');

    return EmotionResult(
      label: label,
      confidence: bestValue * 100.0,
      probabilities: probs,
    );
  }

  void close() {
    if (_loaded) {
      _interpreter.close();
      _loaded = false;
    }
  }
}
