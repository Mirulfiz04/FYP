import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import '../models/emotion_result.dart';
import 'emotion_classifier.dart';

/// Supplies the user's facial emotion while the baseline is being captured, so
/// we can verify they actually look calm. A resting baseline taken while the
/// user is tense/upset would read too high and skew every later "elevated vs.
/// baseline" comparison — this is the camera half of that safeguard.
///
/// Abstracted so tests and headless / no-camera runs can omit it (pass null) or
/// supply a fake.
abstract class BaselineEmotionProbe {
  /// Opens the camera + loads the model. Safe to call before each measurement.
  Future<void> start();

  /// The latest facial emotion, or null when there's no clear face / not ready.
  Future<EmotionResult?> sample();

  /// Releases the camera (keeps the model loaded for the next measurement).
  Future<void> stop();

  /// Releases the camera AND the model — call once when finished for good.
  Future<void> dispose();
}

/// Real probe: runs the front camera + the TFLite emotion classifier, reusing
/// the same model and capture approach as the live session. Every failure is
/// swallowed and surfaces as "no sample" so a missing/blocked camera (e.g. on
/// the emulator) simply yields an "unknown" calmness rather than an error.
class CameraEmotionProbe implements BaselineEmotionProbe {
  final List<CameraDescription> cameras;
  CameraEmotionProbe(this.cameras);

  final EmotionClassifier _classifier = EmotionClassifier();
  CameraController? _controller;
  bool _busy = false;

  @override
  Future<void> start() async {
    if (_controller != null) return; // already running
    try {
      if (cameras.isEmpty) return;
      if (!_classifier.isLoaded) await _classifier.load();
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        front,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      _controller = controller;
    } catch (e) {
      debugPrint('CameraEmotionProbe.start failed: $e');
      _controller = null;
    }
  }

  @override
  Future<EmotionResult?> sample() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _busy) return null;
    _busy = true;
    try {
      final file = await c.takePicture().timeout(const Duration(seconds: 5));
      final result = await _classifier.classifyImageFile(file.path);
      try {
        await File(file.path).delete(); // best-effort temp cleanup
      } catch (_) {}
      return result.probabilities.isEmpty ? null : result;
    } catch (e) {
      return null;
    } finally {
      _busy = false;
    }
  }

  @override
  Future<void> stop() async {
    final c = _controller;
    _controller = null;
    try {
      await c?.dispose();
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    await stop();
    _classifier.close();
  }
}
