import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import '../models/emotion_result.dart';
import '../models/multimodal_result.dart';
import '../models/sensor_reading.dart';
import '../models/session_aggregates.dart';
import '../models/session_summary.dart';
import '../services/ai_config.dart';
import '../services/body_cues.dart';
import '../services/emotion_classifier.dart';
import '../services/emotion_fusion.dart';
import '../services/live_insight_rules.dart';
import '../services/sensor_service.dart';
import '../services/live_session_store.dart';
import '../services/sensor_filter.dart';
import '../services/session_alert_controller.dart';
import '../services/voice_classifier.dart';

enum LiveStatus { active, paused, sensorWarning, ending }

/// Drives a live monitoring session: owns the camera + sensor loops, the
/// elapsed timer, pause/resume, the running aggregates and the local live
/// insight. A [ChangeNotifier] (the app's state approach). All hardware / ML /
/// DB work lives here, not in the UI. The data-feed methods ([onEmotion],
/// [onSensor], [tick]) are public so the logic is unit-testable without
/// hardware.
class LiveSessionController extends ChangeNotifier {
  final List<CameraDescription> cameras;
  final String sessionId;
  final String? userId;
  final int? baselineBpm;

  /// When false, the session runs camera-only: the sensor isn't polled and
  /// heart-rate readings/warnings are suppressed.
  final bool useSensor;

  final LiveSessionStore store;
  final SessionAlertController alerts;

  /// Minimum confidence (%) for a frame to count as a clearly visible face.
  static const double faceConfidenceThreshold = 35;
  static const Set<String> _validQualities = {'GOOD', 'HOLDING HR'};

  LiveSessionController({
    required this.cameras,
    required this.sessionId,
    this.userId,
    this.baselineBpm,
    this.useSensor = true,
    LiveSessionStore? store,
    SessionAlertController? alerts,
  })  : store = store ?? SupabaseLiveSessionStore(),
        alerts = alerts ?? SessionAlertController();

  final _classifier = EmotionClassifier();
  final _voice = VoiceClassifier();
  final _sensorService = createSensorService();
  final _filter = SensorFilter();
  // Seed the fusion with the pre-session baseline (from the readiness screen) so
  // arousal works from frame 1; it then adapts down toward the resting floor.
  late final EmotionFusion _fusion = EmotionFusion(seedBaselineBpm: baselineBpm);
  final _body = BodyCues(); // head pose / eye cues from the face detector

  CameraController? cameraController;
  Timer? _emotionTimer, _sensorTimer, _saveTimer, _clockTimer;

  bool loading = true;
  bool _paused = false;
  bool _ending = false;
  bool _disposed = false;
  bool _classifying = false;
  bool _faceVisible = true;
  bool _hardwareReleased = false;

  EmotionResult emotion = EmotionResult.empty;
  ProcessedSensorReading sensor = ProcessedSensorReading.empty;
  MultimodalResult? multi;
  Duration elapsed = Duration.zero;
  String liveInsight = 'Starting…';
  int savedCount = 0;

  // Voice check-in ("Are you OK?").
  static const Duration _voiceInsightHold = Duration(seconds: 60);
  bool _voiceReady = false;
  bool listening = false; // the mic is recording the answer
  EmotionResult? lastVoice;
  DateTime? _lastVoiceAt;

  /// The voice emotion when the face looks fine but the voice clearly does
  /// not ("says OK, sounds sad"); null when they agree.
  String? voiceMismatch;

  final List<int> hrHistory = []; // last samples for the waveform
  final Map<String, int> _emotionTally = {};
  double _confidenceSum = 0;
  int _confidenceCount = 0;
  final List<int> _hrSamples = [];
  int _faceFrames = 0, _totalFrames = 0;
  int _validSensorFrames = 0, _totalSensorFrames = 0;

  // ---- Read-only state ----------------------------------------------------
  bool get paused => _paused;
  bool get ending => _ending;
  bool get faceVisible => _faceVisible;
  bool get recording => !_paused && !_ending && !loading;
  bool get validBpm =>
      sensor.hr > 0 && _validQualities.contains(sensor.sensorQuality);
  int? get displayBpm => validBpm ? sensor.hr : null;

  /// False when no voice model is bundled — the check-in button is disabled.
  bool get voiceAvailable => _voiceReady;

  LiveStatus get status {
    if (_ending) return LiveStatus.ending;
    if (_paused) return LiveStatus.paused;
    if (alerts.currentAlert != null) return LiveStatus.sensorWarning;
    return LiveStatus.active;
  }

  String get currentState {
    if (multi != null) return multi!.wellbeing;
    return switch (emotion.label) {
      'Happy' || 'Surprise' => 'Content',
      'Neutral' => 'Calm',
      'Detecting...' => '—',
      _ => 'Low',
    };
  }

  // ---- Hardware orchestration (not exercised by unit tests) ----------------

  Future<void> start() async {
    try {
      await _classifier.load();
      try {
        await _voice.load();
        _voiceReady = true;
      } catch (e) {
        debugPrint('⚠️ Voice model not loaded, check-in disabled: $e');
      }
      await _initCamera();
      if (_disposed) return;
      alerts.setCameraReady();
      alerts.setAiAvailable(AiConfig.hasKey);
      alerts.cameraOnlyMode = !useSensor;
      loading = false;
      _recomputeInsight();
      notifyListeners();

      if (useSensor) {
        _sensorTimer =
            Timer.periodic(const Duration(seconds: 1), (_) => _fetchSensor());
      }
      _emotionTimer = Timer.periodic(
          const Duration(milliseconds: 1500), (_) => _classifyFrame());
      _saveTimer =
          Timer.periodic(const Duration(seconds: 5), (_) => _saveReading());
      _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
      if (useSensor) unawaited(_fetchSensor());
    } catch (e) {
      final code = e is CameraException ? e.code.toLowerCase() : '';
      if (code.contains('access') ||
          code.contains('permission') ||
          code.contains('denied')) {
        alerts.setCameraPermissionRequired();
      }
      loading = false;
      notifyListeners();
    }
  }

  /// Opens the front camera. On the emulator the physical camera can still be
  /// releasing from the readiness-screen baseline probe when we reach here, so
  /// the first `initialize()` may fail transiently with a "Broken pipe" /
  /// camera-in-use error. We retry a few times with a growing backoff so the
  /// session self-heals once the previous owner finishes releasing. A
  /// permission/access denial won't fix itself on retry, so it's surfaced
  /// immediately for the UI to prompt.
  Future<void> _initCamera() async {
    if (cameras.isEmpty) throw Exception('No camera found');
    final front = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    const maxAttempts = 4;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (_disposed) return;
      final controller = CameraController(front, ResolutionPreset.low,
          enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
      try {
        await controller.initialize();
        if (_disposed) {
          await controller.dispose();
          return;
        }
        cameraController = controller;
        return;
      } catch (e) {
        // Free the half-open controller before retrying so we never stack up
        // camera clients on the emulator's single device.
        try {
          await controller.dispose();
        } catch (_) {}
        final code = e is CameraException ? e.code.toLowerCase() : '';
        final isPermission = code.contains('access') ||
            code.contains('permission') ||
            code.contains('denied');
        if (isPermission || attempt == maxAttempts) rethrow;
        // Back off a little longer each attempt to let the prior camera release.
        await Future.delayed(Duration(milliseconds: 300 * attempt));
      }
    }
  }

  Future<void> retryCamera() async {
    try {
      await cameraController?.dispose();
      cameraController = null;
      await _initCamera();
      if (_disposed) return;
      alerts.setCameraReady();
      notifyListeners();
    } catch (_) {
      alerts.setCameraPermissionRequired();
    }
  }

  Future<void> retrySensor() => _fetchSensor();

  Future<void> _fetchSensor() async {
    try {
      final raw = await _sensorService.fetchReading();
      onSensor(_filter.process(raw));
    } catch (_) {
      onSensor(ProcessedSensorReading(
        hr: sensor.hr,
        spo2: sensor.spo2,
        sensorQuality: 'DISCONNECTED',
        hrSource: sensor.hrSource,
        hrQuality: 'esp32_disconnected',
        rawHr: sensor.rawHr,
        algoHr: sensor.algoHr,
        instantHr: sensor.instantHr,
        sourceHr: sensor.sourceHr,
        fixedHr: sensor.fixedHr,
        ir: sensor.ir,
        red: sensor.red,
      ));
    }
  }

  Future<void> _classifyFrame() async {
    final controller = cameraController;
    // While paused (or ending) we keep the camera connected but stop the heavy
    // capture + inference work — that frees the UI thread so Pause/Resume stay
    // responsive and recording is truly paused.
    if (_disposed ||
        _paused ||
        _ending ||
        controller == null ||
        !controller.value.isInitialized ||
        _classifying) {
      return;
    }
    _classifying = true;
    try {
      final file =
          await controller.takePicture().timeout(const Duration(seconds: 5));
      if (_disposed) return;
      await File(file.path).length();
      final result = await _classifier.classifyImageFile(file.path);
      if (_disposed) return;
      final face = _classifier.lastFace;
      if (face != null) _body.add(face);
      final faceVisible = result.probabilities.isNotEmpty &&
          result.confidence >= faceConfidenceThreshold;
      final fused = result.probabilities.isEmpty
          ? null
          : _fusion.process(result, _classifier.labels, sensor, body: _body);
      onEmotion(fused?.emotion ?? result, faceVisible: faceVisible, fused: fused);
    } catch (_) {
      if (!_disposed) onEmotion(emotion, faceVisible: false);
    } finally {
      _classifying = false;
    }
  }

  /// "Are you OK?" — records a short spoken answer and blends its tone into
  /// the emotion for the next few seconds. Returns the voice result, or null
  /// if the mic permission was denied or nothing was said.
  Future<EmotionResult?> voiceCheckIn() async {
    if (!_voiceReady || listening || !recording) return null;
    listening = true;
    notifyListeners();
    try {
      final audio = await _voice.record();
      if (audio == null || _disposed) return null;
      final result = _voice.classify(audio);
      if (result.probabilities.isEmpty) return null;
      onVoice(result);
      return result;
    } catch (e) {
      debugPrint('⚠️ Voice check-in failed: $e');
      return null;
    } finally {
      listening = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _saveReading() async {
    if (!recording || emotion.label == 'Detecting...') return;
    try {
      await store.saveReading(
        sessionId: sessionId,
        emotion: emotion.label,
        confidence: emotion.confidence,
        hr: sensor.hr,
        spo2: sensor.spo2,
        sensorQuality: sensor.sensorQuality,
      );
      savedCount++;
      notifyListeners();
    } catch (_) {/* per-reading save is best-effort */}
  }

  // ---- Public, testable data feed -----------------------------------------

  void onEmotion(EmotionResult display,
      {required bool faceVisible, MultimodalResult? fused}) {
    emotion = display;
    if (fused != null) multi = fused;
    _faceVisible = faceVisible;
    alerts.onFrame(faceVisible: faceVisible);

    if (recording) {
      _totalFrames++;
      if (faceVisible) _faceFrames++;
      if (display.label != 'Detecting...') {
        _emotionTally[display.label] = (_emotionTally[display.label] ?? 0) + 1;
        _confidenceSum += display.confidence;
        _confidenceCount++;
      }
    }
    _recomputeInsight();
    notifyListeners();
  }

  void onSensor(ProcessedSensorReading reading) {
    sensor = reading;
    alerts.onSensorQuality(reading.sensorQuality);
    if (validBpm) {
      hrHistory.add(reading.hr);
      if (hrHistory.length > 40) hrHistory.removeAt(0);
    }
    if (recording) {
      _totalSensorFrames++;
      if (validBpm) {
        _validSensorFrames++;
        _hrSamples.add(reading.hr);
      }
    }
    _recomputeInsight();
    notifyListeners();
  }

  void onVoice(EmotionResult voice, {DateTime? at}) {
    lastVoice = voice;
    _lastVoiceAt = at ?? DateTime.now();
    _fusion.addVoice(voice.probabilities, _voice.labels, _classifier.labels,
        at: _lastVoiceAt);
    voiceMismatch = EmotionFusion.voiceMismatch(emotion.label, voice);
    _recomputeInsight();
    notifyListeners();
  }

  void tick() {
    if (_paused || _ending || loading) return;
    elapsed += const Duration(seconds: 1);
    notifyListeners();
  }

  /// Test hook: marks the session "running" without starting the camera, so the
  /// data-feed + aggregate logic can be exercised in unit tests.
  @visibleForTesting
  void beginForTest() {
    loading = false;
    notifyListeners();
  }

  void pause() {
    if (_ending) return;
    _paused = true;
    notifyListeners();
  }

  void resume() {
    if (_ending) return;
    _paused = false;
    notifyListeners();
  }

  /// Stops the session, builds + saves the aggregates. Returns true only when
  /// the save succeeded (so the caller avoids claiming success on failure).
  Future<bool> stop() async {
    _ending = true;
    _emotionTimer?.cancel();
    _sensorTimer?.cancel();
    _saveTimer?.cancel();
    _clockTimer?.cancel();
    notifyListeners();
    return store.complete(sessionId, buildAggregates());
  }

  /// Tears down the camera + ML isolates. Call this *before* firing the
  /// session-complete notification and navigating to the results page.
  ///
  /// On Android, closing the camera HAL (and the ML Kit detector / TFLite
  /// isolate) is a heavy platform-thread operation. Left to run during widget
  /// disposal, it collided with the completion notification and the page
  /// transition — which made the notification sound stutter and the results
  /// screen appear late. Doing it here, up front, lets that jank happen behind
  /// the "ending" spinner so the notification + results land on a free thread.
  ///
  /// Idempotent: safe to call again from [dispose].
  Future<void> releaseHardware() async {
    if (_hardwareReleased) return;
    _hardwareReleased = true;
    _emotionTimer?.cancel(); // no new captures while we tear down
    // Let an in-flight capture/classify unwind before we kill the isolate it's
    // using (up to ~0.5s), so we never close the interpreter mid-run.
    for (var i = 0; _classifying && i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    // Null the controller first so any rebuild renders the placeholder instead
    // of touching a disposed controller.
    final cam = cameraController;
    cameraController = null;
    try {
      await cam?.dispose();
    } catch (_) {}
    try {
      _classifier.close();
      _voice.close();
    } catch (_) {}
  }

  SessionAggregates buildAggregates() {
    final dominant = _emotionTally.isEmpty
        ? 'Neutral'
        : _emotionTally.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    final avgConf = _confidenceCount == 0 ? 0.0 : _confidenceSum / _confidenceCount;
    final avg = _hrSamples.isEmpty
        ? 0
        : (_hrSamples.reduce((a, b) => a + b) / _hrSamples.length).round();
    final min = _hrSamples.isEmpty ? 0 : _hrSamples.reduce((a, b) => a < b ? a : b);
    final max = _hrSamples.isEmpty ? 0 : _hrSamples.reduce((a, b) => a > b ? a : b);
    return SessionAggregates(
      dominantEmotion: dominant,
      averageConfidence: double.parse(avgConf.toStringAsFixed(1)),
      baselineBpm: baselineBpm,
      averageBpm: avg,
      minimumBpm: min,
      maximumBpm: max,
      finalState: SessionSummary.deriveFinalState(dominant, avg),
      cameraQuality: _ratioQuality(_faceFrames, _totalFrames),
      sensorQuality: _ratioQuality(_validSensorFrames, _totalSensorFrames),
      readingsSaved: savedCount,
    );
  }

  String _ratioQuality(int good, int total) {
    if (total == 0) return 'Fair';
    final r = good / total;
    if (r >= 0.8) return 'Good';
    if (r >= 0.5) return 'Fair';
    return 'Poor';
  }

  void _recomputeInsight() {
    final voiceAt = _lastVoiceAt;
    if (voiceMismatch != null &&
        voiceAt != null &&
        DateTime.now().difference(voiceAt) < _voiceInsightHold) {
      liveInsight = "You said you're OK, but your voice sounds "
          '${voiceMismatch!.toLowerCase()}. Take a moment if you need it.';
      return;
    }
    // A sustained head/eye cue (only while the face is visible — the window
    // may still hold frames from before the face was lost).
    final cue = _faceVisible ? _body.insight : null;
    if (cue != null) {
      liveInsight = cue;
      return;
    }
    if (!useSensor) {
      liveInsight = _faceVisible
          ? 'Emotion readings are currently stable.'
          : 'Face is not clearly visible.';
      return;
    }
    liveInsight = LiveInsightRules.evaluate(
      faceVisible: _faceVisible,
      sensorQuality: sensor.sensorQuality,
      hr: sensor.hr,
      validBpm: validBpm,
      baselineBpm: baselineBpm,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _emotionTimer?.cancel();
    _sensorTimer?.cancel();
    _saveTimer?.cancel();
    _clockTimer?.cancel();
    // If the session ended cleanly, releaseHardware() already did this; guard
    // against a double dispose/close.
    if (!_hardwareReleased) {
      _hardwareReleased = true;
      cameraController?.dispose();
      _classifier.close();
      _voice.close();
    }
    cameraController = null;
    alerts.dispose();
    super.dispose();
  }
}
