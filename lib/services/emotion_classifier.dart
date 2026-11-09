import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as imglib;
import 'package:tflite_flutter/tflite_flutter.dart';
import '../models/emotion_result.dart';
import 'body_cues.dart';

class EmotionClassifier {
  static const int inputSize = 224;

  /// Set to true to log every frame's decode + probabilities + emotion. Off by
  /// default so debug runs aren't slowed down by per-frame console spam. Startup
  /// and error logs are always kept.
  static const bool logFrames = false;

  /// Detect the face and classify only that crop (instead of a centre crop of
  /// the whole frame). This is the single biggest accuracy win: the model was
  /// trained on face-filling images, so feeding it the actual face closes the
  /// train/test gap. Frames with no face are skipped (return [EmotionResult.empty]).
  static const bool faceCropEnabled = true;

  /// Test-time augmentation: also classify the horizontally-flipped crop and
  /// average — a cheap, small accuracy boost for a symmetric task like FER.
  ///
  /// OFF by default: it doubles the model runs per frame, and during a live
  /// session that extra latency (and battery) isn't worth the tiny accuracy
  /// gain. Flip to `true` only for offline/one-shot classification where speed
  /// doesn't matter.
  static const bool ttaEnabled = false;

  /// Number of CPU threads the interpreter may use. On the emulator and most
  /// phones the model runs several times faster with 4 threads than 1.
  static const int _inferenceThreads = 4;

  /// How much to pad the detected face box (1.0 = tight, 1.4 = 40% margin) so
  /// the crop includes forehead/chin/context the way training images did.
  static const double _faceMargin = 1.4;

  /// Downscale the frame to at most this long-side before running detection —
  /// faster, and plenty for locating a face we then re-crop. Kept small because
  /// detection re-encodes a JPEG on the UI thread every frame, so a smaller
  /// image is a direct latency win.
  static const int _detectMaxSide = 320;

  /// JPEG quality for the throwaway image handed to the face detector. It's
  /// only used to locate a box, so it doesn't need to be high quality.
  static const int _detectJpegQuality = 75;

  late final Interpreter _interpreter;
  late final IsolateInterpreter _isolateInterpreter;
  late final List<String> _labels;
  FaceDetector? _faceDetector;
  FaceFrame? _lastFace;
  bool _loaded = false;

  bool get isLoaded => _loaded;

  /// Head pose + eyes-open/smile of the face classified by the last
  /// [classifyImageFile] call; null when no face was cropped. Read it right
  /// after that call — the next call overwrites it.
  FaceFrame? get lastFace => _lastFace;

  /// Class labels in model-output order (empty until [load] completes).
  /// The fusion layer needs this to map re-weighted probabilities back to a
  /// label.
  List<String> get labels => _loaded ? _labels : const <String>[];

  Future<void> load() async {
    // Multi-threaded native inference, run on a background isolate so the heavy
    // per-frame model run never blocks the UI thread (the main cause of the
    // camera stutter during a live session).
    final options = InterpreterOptions()..threads = _inferenceThreads;
    _interpreter = await Interpreter.fromAsset('assets/model.tflite',
        options: options);
    _isolateInterpreter =
        await IsolateInterpreter.create(address: _interpreter.address);
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

    if (faceCropEnabled) {
      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          performanceMode: FaceDetectorMode.fast,
          minFaceSize: 0.15,
          // Eyes-open + smiling probabilities for the body cues (BodyCues).
          enableClassification: true,
        ),
      );
    }

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
    _lastFace = null;
    if (!_loaded) {
      debugPrint('⚠️ classify skipped: model not loaded yet');
      return EmotionResult.empty;
    }

    // Everything below is wrapped so a failure at ANY stage (decode, resize,
    // tensor build, native run) is logged with the exact cause instead of
    // silently leaving the UI stuck on "Detecting…".
    try {
      final bytes = await File(imagePath).readAsBytes();
      // Decode + bake orientation + downscale run on a background isolate
      // (compute): pure-Dart JPEG decode is the heaviest per-frame CPU cost and
      // on the UI thread it's what stuttered the camera preview. The isolate
      // returns the small RGB buffer plus a re-encoded JPEG for the detector.
      final prep = await compute(_prepFrame, bytes);
      if (prep == null) {
        debugPrint('⚠️ Could not decode image (${bytes.length} bytes): $imagePath');
        return EmotionResult.empty;
      }
      if (logFrames) {
        debugPrint(
            '🖼️ Prepped frame ${prep.width}x${prep.height} (${bytes.length} bytes)');
      }

      // Wrap the raw RGB buffer back into an Image — a cheap view, no re-decode.
      final image = imglib.Image.fromBytes(
        width: prep.width,
        height: prep.height,
        bytes: prep.rgb.buffer,
        numChannels: 3,
        order: imglib.ChannelOrder.rgb,
      );

      // Choose the region to classify: the detected face crop (preferred), or a
      // centre-square crop as a fallback when detection isn't available/fails.
      imglib.Image faceImg;
      if (faceCropEnabled && _faceDetector != null) {
        try {
          final cropped = await _cropDetectedFace(image, prep.probeJpeg);
          if (cropped == null) {
            // Detection ran and found no face → skip this frame rather than
            // classify background (which used to read as Neutral/Sad).
            if (logFrames) debugPrint('👤 No face detected — frame skipped');
            return EmotionResult.empty;
          }
          faceImg = cropped;
        } catch (e) {
          debugPrint('⚠️ Face detection failed, using centre crop: $e');
          faceImg = imglib.copyResizeCropSquare(image, size: inputSize);
        }
      } else {
        faceImg = imglib.copyResizeCropSquare(image, size: inputSize);
      }

      // Inference on the crop, optionally averaged with its mirror (TTA).
      var probs = await _infer(faceImg);
      if (ttaEnabled) {
        final mirror = await _infer(imglib.flipHorizontal(faceImg));
        probs = _averageProbs(probs, mirror);
      }
      if (logFrames) debugPrint('🧠 Probs: $probs');

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
      if (logFrames) {
        debugPrint('🎭 Emotion: $label  (${(bestValue * 100).toStringAsFixed(1)}%)');
      }

      return EmotionResult(
        label: label,
        confidence: bestValue * 100.0,
        probabilities: probs,
      );
    } catch (e, st) {
      debugPrint('⚠️ classifyImageFile failed: $e');
      debugPrint('$st');
      return EmotionResult.empty;
    }
  }

  /// Runs the model on a 224×224 RGB image and returns a probability vector.
  ///
  /// Teachable Machine models expect RGB normalised to [-1, 1]
  /// ((pixel / 127.5) - 1.0), NOT [0, 1] — [0, 1] gave weak/wrong predictions.
  Future<List<double>> _infer(imglib.Image img) async {
    // Pull the whole RGB buffer in one bulk copy. The old code called
    // getPixel() for every pixel, which allocates a Pixel object 224*224 times
    // per frame and was a big chunk of the on-thread cost; getBytes avoids all
    // of that.
    final bytes = img.getBytes(order: imglib.ChannelOrder.rgb);
    var p = 0;
    final input = [
      List.generate(
        inputSize,
        (_) => List.generate(
          inputSize,
          (_) => [
            bytes[p++] / 127.5 - 1.0,
            bytes[p++] / 127.5 - 1.0,
            bytes[p++] / 127.5 - 1.0,
          ],
        ),
      ),
    ];

    final outputSize = _interpreter.getOutputTensor(0).shape.last;
    final output = [List<double>.filled(outputSize, 0.0)];
    // Runs on the worker isolate — the native inference no longer blocks the UI.
    await _isolateInterpreter.run(input, output);
    return _toProbabilities(output.first);
  }

  List<double> _averageProbs(List<double> a, List<double> b) {
    if (a.length != b.length || a.isEmpty) return a;
    return List<double>.generate(a.length, (i) => (a[i] + b[i]) / 2.0);
  }

  /// Detects the largest face in the already-downscaled, orientation-baked
  /// [small] image and returns a square 224×224 crop padded by [_faceMargin].
  /// [probeJpeg] is the JPEG of [small] (encoded off-thread in [_prepFrame]) —
  /// the exact same pixels the box coordinates refer to, so the crop lines up.
  /// Returns null if no face is found; throws if the detector itself errors
  /// (caller falls back to a centre crop).
  Future<imglib.Image?> _cropDetectedFace(
      imglib.Image small, Uint8List probeJpeg) async {
    final tmp = File('${Directory.systemTemp.path}/meds_face_probe.jpg');
    await tmp.writeAsBytes(probeJpeg, flush: true);

    final faces =
        await _faceDetector!.processImage(InputImage.fromFilePath(tmp.path));
    if (faces.isEmpty) return null;

    // Largest face by box area.
    faces.sort((a, b) => (b.boundingBox.width * b.boundingBox.height)
        .compareTo(a.boundingBox.width * a.boundingBox.height));
    final face = faces.first;
    final box = face.boundingBox;

    // Square crop centred on the face, padded, clamped to the image.
    final cx = box.left + box.width / 2;
    final cy = box.top + box.height / 2;
    final side = math.max(box.width, box.height) * _faceMargin;
    final x0 = (cx - side / 2).round().clamp(0, small.width - 1);
    final y0 = (cy - side / 2).round().clamp(0, small.height - 1);
    final x1 = (cx + side / 2).round().clamp(x0 + 1, small.width);
    final y1 = (cy + side / 2).round().clamp(y0 + 1, small.height);
    final w = x1 - x0;
    final h = y1 - y0;
    if (w < 8 || h < 8) return null;

    _lastFace = FaceFrame(
      pitch: face.headEulerAngleX,
      yaw: face.headEulerAngleY,
      roll: face.headEulerAngleZ,
      leftEyeOpen: face.leftEyeOpenProbability,
      rightEyeOpen: face.rightEyeOpenProbability,
      smile: face.smilingProbability,
    );
    final cropped = imglib.copyCrop(small, x: x0, y: y0, width: w, height: h);
    return imglib.copyResize(cropped, width: inputSize, height: inputSize);
  }

  void close() {
    if (_loaded) {
      _isolateInterpreter.close();
      _interpreter.close();
      _faceDetector?.close();
      _faceDetector = null;
      _loaded = false;
    }
  }
}

/// Runs on a background isolate (via [compute]): decode the camera JPEG, bake
/// EXIF orientation, and downscale to the detection size. Returns the small RGB
/// buffer (to wrap back into an Image) plus a re-encoded JPEG for the face
/// detector. All the heavy pure-Dart image work happens here so the UI thread
/// stays free and the camera preview doesn't stutter. Returns null if the bytes
/// can't be decoded.
_FramePrep? _prepFrame(Uint8List bytes) {
  // Camera saves JPEG, so try the JPEG decoder first (faster, avoids
  // format-detection edge cases), then fall back to auto-detect.
  var decoded = imglib.decodeJpg(bytes);
  decoded ??= imglib.decodeImage(bytes);
  if (decoded == null) return null;

  final image = imglib.bakeOrientation(decoded);
  final maxSide = math.max(image.width, image.height);
  final scale = maxSide > EmotionClassifier._detectMaxSide
      ? EmotionClassifier._detectMaxSide / maxSide
      : 1.0;
  final small = scale < 1.0
      ? imglib.copyResize(
          image,
          width: (image.width * scale).round(),
          height: (image.height * scale).round(),
        )
      : image;

  final probe = Uint8List.fromList(
      imglib.encodeJpg(small, quality: EmotionClassifier._detectJpegQuality));
  final rgb =
      Uint8List.fromList(small.getBytes(order: imglib.ChannelOrder.rgb));
  return _FramePrep(rgb, small.width, small.height, probe);
}

/// The result of [_prepFrame], sent back from the background isolate.
class _FramePrep {
  _FramePrep(this.rgb, this.width, this.height, this.probeJpeg);
  final Uint8List rgb;
  final int width;
  final int height;
  final Uint8List probeJpeg;
}
