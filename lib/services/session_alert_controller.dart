import 'package:flutter/foundation.dart';

import '../models/app_notification.dart';

/// Health of one subsystem, shown as a status indicator chip.
enum IndicatorState { ok, warning, error, unknown }

/// An ongoing sensor/camera problem during a live session.
class SessionAlert {
  final NotificationType type;
  final String message;
  final bool hasRetry; // -> "Retry Connection"
  final bool hasOpenSettings; // -> "Open Settings" / "Allow Camera"

  const SessionAlert({
    required this.type,
    required this.message,
    this.hasRetry = false,
    this.hasOpenSettings = false,
  });

  // Canonical, spec-worded messages.
  static const _sensorDisconnected =
      'Heart-rate sensor disconnected. Please reconnect the device before continuing.';
  static const _noFinger =
      'No finger detected. Place your finger gently on the heart-rate sensor.';
  static const _cameraPermission =
      'Camera permission is required for facial-emotion detection.';
  static const _faceNotVisible =
      'Your face is not clearly visible. Face the camera and ensure sufficient lighting.';
  static const _lowQuality =
      'Heart-rate sensor signal is unstable. Keep your finger still and adjust its position.';

  static const sensorDisconnected = SessionAlert(
      type: NotificationType.sensorDisconnected,
      message: _sensorDisconnected,
      hasRetry: true);
  static const noFinger = SessionAlert(
      type: NotificationType.noFingerDetected, message: _noFinger);
  static const cameraPermission = SessionAlert(
      type: NotificationType.cameraPermissionRequired,
      message: _cameraPermission,
      hasOpenSettings: true);
  static const faceNotVisible = SessionAlert(
      type: NotificationType.faceNotVisible, message: _faceNotVisible);
  static const lowQuality = SessionAlert(
      type: NotificationType.lowSensorQuality, message: _lowQuality);
}

/// Drives the live-session warning banner, transient SnackBars and the three
/// status indicators (Camera / Heart-rate Sensor / AI Service).
///
/// Pure logic + a [ChangeNotifier] so it follows the app's existing state
/// approach and is fully unit-testable (inject [clock] in tests). It never
/// imports Flutter Material, the camera plugin or Supabase.
class SessionAlertController extends ChangeNotifier {
  /// How many consecutive low-confidence/empty frames before we declare the
  /// face "not clearly visible".
  static const int faceMissThreshold = 4;

  /// Cooldown so a flapping problem does not emit a new SnackBar / centre entry
  /// every frame. Spec asks for ~5–10s; 7s sits in the middle.
  final Duration cooldown;
  final DateTime Function() _clock;

  /// Reserved hook: when true, a future "camera-only mode" can ignore sensor
  /// problems for gating. The controller still reports them either way.
  bool cameraOnlyMode;

  SessionAlertController({
    this.cooldown = const Duration(seconds: 7),
    this.cameraOnlyMode = false,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  // ---- Subsystem state ----------------------------------------------------
  IndicatorState _camera = IndicatorState.unknown;
  IndicatorState _sensor = IndicatorState.unknown;
  IndicatorState _ai = IndicatorState.unknown;

  IndicatorState get cameraState => _camera;
  IndicatorState get sensorState => _sensor;
  IndicatorState get aiState => _ai;

  bool _cameraPermissionDenied = false;
  String _sensorQuality = 'WAITING';
  int _missingFaceFrames = 0;

  final Map<NotificationType, DateTime> _lastEmit = {};

  // ---- Inputs from the dashboard -----------------------------------------

  void setCameraReady() {
    _cameraPermissionDenied = false;
    _setCamera(IndicatorState.ok);
  }

  void setCameraPermissionRequired() {
    _cameraPermissionDenied = true;
    _setCamera(IndicatorState.error);
  }

  void setAiAvailable(bool available) {
    _setAi(available ? IndicatorState.ok : IndicatorState.warning);
  }

  /// Feed the processed sensor quality string each tick.
  void onSensorQuality(String quality) {
    if (_sensorQuality == quality) return;
    _sensorQuality = quality;
    _sensor = switch (quality) {
      'GOOD' || 'HOLDING HR' => IndicatorState.ok,
      'WAITING' => IndicatorState.unknown,
      'NO FINGER' || 'BAD SIGNAL' => IndicatorState.warning,
      'DISCONNECTED' => IndicatorState.error,
      _ => IndicatorState.unknown,
    };
    notifyListeners();
  }

  /// Feed whether the latest frame contained a clearly visible face.
  void onFrame({required bool faceVisible}) {
    final before = _faceProblem;
    if (faceVisible) {
      _missingFaceFrames = 0;
    } else {
      _missingFaceFrames++;
    }
    if (_faceProblem != before) notifyListeners();
  }

  bool get _faceProblem => _missingFaceFrames >= faceMissThreshold;

  // ---- Derived banner -----------------------------------------------------

  /// The single highest-priority ongoing problem, or null when all is well.
  SessionAlert? get currentAlert {
    if (_cameraPermissionDenied) return SessionAlert.cameraPermission;
    switch (_sensorQuality) {
      case 'DISCONNECTED':
        return SessionAlert.sensorDisconnected;
      case 'NO FINGER':
        return SessionAlert.noFinger;
    }
    if (_faceProblem) return SessionAlert.faceNotVisible;
    if (_sensorQuality == 'BAD SIGNAL') return SessionAlert.lowQuality;
    return null;
  }

  /// Cooldown gate for transient emissions (SnackBars / centre entries). Returns
  /// true at most once per [cooldown] window per notification [type], so a
  /// repeated low-signal condition does not spam the user.
  bool shouldEmit(NotificationType type) {
    final now = _clock();
    final last = _lastEmit[type];
    if (last != null && now.difference(last) < cooldown) return false;
    _lastEmit[type] = now;
    return true;
  }

  void _setCamera(IndicatorState s) {
    if (_camera == s) return;
    _camera = s;
    notifyListeners();
  }

  void _setAi(IndicatorState s) {
    if (_ai == s) return;
    _ai = s;
    notifyListeners();
  }
}
