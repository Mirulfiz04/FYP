import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/session_readiness.dart';
import '../services/baseline_emotion_probe.dart';
import '../services/baseline_history_service.dart';
import '../services/baseline_measurement_service.dart';
import '../services/device_check_service.dart';

/// Orchestrates the pre-flight checks + baseline measurement. A [ChangeNotifier]
/// like the app's other controllers; the screen reads [state] and the computed
/// [SessionReadiness.canStartSession]. Device + baseline logic is delegated to
/// the injected services (real or mock).
class SessionReadinessController extends ChangeNotifier {
  final DeviceCheckService deviceService;
  final BaselineMeasurementService baselineService;

  /// Optional camera probe used during the baseline to check the user looks
  /// calm. Null in tests / camera-less runs (calmness then stays unknown).
  final BaselineEmotionProbe? emotionProbe;

  /// Optional source of the user's past baselines, used to personalise the
  /// "elevated baseline" check. Null → the fixed ceiling is used.
  final BaselineHistoryService? historyService;

  final SessionReadiness state = SessionReadiness();

  /// Polls the sensor while the screen is open so finger placement is picked up
  /// live (no manual "Check Again" tap).
  static const Duration _pollInterval = Duration(milliseconds: 1500);
  Timer? _poll;
  bool _sensorBusy = false; // guards against overlapping sensor reads
  bool _disposed = false;
  Future<void>? _baselineRun; // the in-flight measurement, if any

  SessionReadinessController({
    required this.deviceService,
    required this.baselineService,
    this.emotionProbe,
    this.historyService,
  });

  bool get canStart => state.canStartSession;

  /// Loads the user's personal resting baseline (median of recent sessions) so
  /// the "elevated baseline" check adapts to them. Best-effort and independent
  /// of the device checks — safe to call once when the screen opens.
  Future<void> loadPersonalBaseline() async {
    final svc = historyService;
    if (svc == null) return;
    try {
      final recent = await svc.recentBaselines();
      state
        ..personalRestingBpm = SessionReadiness.personalMedianFrom(recent)
        ..personalBaselineCount = recent.length;
      _notify();
    } catch (_) {
      // Leave personal data unset → fixed-ceiling fallback.
    }
  }

  /// Re-runs camera, sensor (when enabled) and system checks (not the baseline).
  Future<void> runChecks() async {
    await Future.wait([
      _runCamera(),
      if (state.useSensor) _runSensor(),
      _runSystem(),
    ]);
  }

  /// Starts the live sensor poll: every [_pollInterval] we refresh the sensor
  /// status, and the moment a finger is detected we kick off the baseline
  /// automatically. Safe to call more than once.
  void startLiveSensorDetection() {
    _poll ??= Timer.periodic(_pollInterval, (_) => _pollSensor());
  }

  void stopLiveSensorDetection() {
    _poll?.cancel();
    _poll = null;
  }

  /// One live poll tick. Skips itself while a measurement or another read is in
  /// flight (those already drive the sensor), and updates the status quietly
  /// (without flashing every row back to "Checking…").
  Future<void> _pollSensor() async {
    if (!state.useSensor ||
        _sensorBusy ||
        state.baselineStatus == BaselineStatus.measuring) {
      return;
    }
    await _readSensor();
  }

  /// Toggles the heart-rate sensor on/off (camera-only mode). Re-checks the
  /// sensor when turning it back on.
  void setUseSensor(bool value) {
    state.useSensor = value;
    _notify();
    if (value) _runSensor();
  }

  Future<void> retryCamera() => _runCamera();
  Future<void> retrySensor() => _runSensor();
  Future<void> retrySystem() => _runSystem();

  Future<void> _runCamera() async {
    state
      ..cameraPermission = CameraPermission.checking
      ..cameraConnection = CameraConnection.checking
      ..faceVisibility = FaceVisibility.checking;
    _notify();
    final c = await deviceService.checkCamera();
    state
      ..cameraPermission = c.permission
      ..cameraConnection = c.connection
      ..faceVisibility = c.face;
    _notify();
  }

  /// Explicit sensor check (manual "Check Again" / sensor toggle): shows the
  /// "Checking…" state first, then reads.
  Future<void> _runSensor() async {
    state
      ..sensorConnection = SensorConnection.checking
      ..fingerDetection = FingerDetection.checking
      ..signalQuality = SignalQuality.checking;
    _notify();
    await _readSensor();
  }

  /// Reads the sensor once and applies the result. Shared by the explicit check
  /// and the live poll. The moment a finger lands on a connected sensor we kick
  /// off the baseline automatically — no manual "Measure Baseline" tap.
  Future<void> _readSensor() async {
    if (_sensorBusy) return;
    _sensorBusy = true;
    final wasFingerDetected = state.fingerDetected;
    try {
      final s = await deviceService.checkSensor();
      state
        ..sensorConnection = s.connection
        ..fingerDetection = s.finger
        ..signalQuality = s.signal;
      if (s.bpm != null) state.currentBpm = s.bpm;
      _notify();
    } finally {
      _sensorBusy = false;
    }

    // Auto-start the baseline when a finger is on a connected sensor and we
    // haven't already got one (or are measuring). It fires either on the first
    // detection (`notStarted`) or whenever the finger is freshly *re-placed*
    // (a notDetected→detected edge) — so lifting and replacing your finger
    // retries a failed baseline, while a finger left resting after a failure
    // doesn't loop.
    final fingerJustPlaced = !wasFingerDetected && state.fingerDetected;
    final canMeasure = state.baselineStatus != BaselineStatus.measuring &&
        state.baselineStatus != BaselineStatus.completed;
    if (state.useSensor &&
        state.sensorConnected &&
        state.fingerDetected &&
        canMeasure &&
        (state.baselineStatus == BaselineStatus.notStarted ||
            fingerJustPlaced)) {
      measureBaseline();
    }
  }

  Future<void> _runSystem() async {
    state.storage = StorageStatus.checking;
    _notify();
    final sys = await deviceService.checkSystem();
    state
      ..storage = sys.storage
      ..internet = sys.internet
      ..aiService = sys.ai;
    _notify();
  }

  /// Collects a stable baseline heart rate (and, via the camera probe, whether
  /// the user looked calm while doing it). Idempotent: if a measurement is
  /// already running, returns that same in-flight future instead of starting a
  /// second one — so auto-start and a manual tap can't overlap.
  Future<void> measureBaseline() => _baselineRun ??= _runBaseline();

  Future<void> _runBaseline() async {
    state
      ..baselineStatus = BaselineStatus.measuring
      ..baselineProgress = 0
      ..baselineCalmness = BaselineCalmness.unknown;
    _notify();
    try {
      final result = await baselineService.measure(
        emotionProbe: emotionProbe,
        onTick: (bpm, progress) {
          state
            ..currentBpm = bpm
            ..baselineProgress = progress;
          _notify();
        },
      );

      if (result.ok) {
        state
          ..baselineStatus = BaselineStatus.completed
          ..baselineBpm = result.bpm
          ..baselineCalmness = result.calmness
          ..baselineProgress = 1;
      } else {
        state.baselineStatus = BaselineStatus.failed;
      }
      _notify();
    } finally {
      _baselineRun = null;
    }
  }

  void togglePrep(String key, bool value) {
    state.togglePrep(key, value);
    _notify();
  }

  /// Releases the baseline camera probe's camera and awaits it, so the next
  /// screen (the live session) can open the front camera without racing this
  /// screen's still-closing one — the overlap otherwise fails with a "Broken
  /// pipe" on the emulator's single camera. Call before navigating away. The
  /// model stays loaded and is freed in [dispose]; safe to call more than once.
  Future<void> releaseCamera() async {
    await emotionProbe?.stop();
  }

  /// notifyListeners that's safe to call from async callbacks that may finish
  /// after the screen (and this controller) is gone.
  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    stopLiveSensorDetection();
    emotionProbe?.dispose();
    super.dispose();
  }
}
