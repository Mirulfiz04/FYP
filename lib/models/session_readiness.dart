/// Visual severity of a single check, used to pick an icon + colour.
enum CheckLevel { idle, checking, ok, warn, error }

// ---- Per-check status enums ------------------------------------------------
enum CameraPermission { checking, granted, denied }

enum CameraConnection { checking, connected, unavailable }

enum FaceVisibility { checking, detected, notVisible, poorLighting, multipleFaces }

enum SensorConnection { checking, connected, disconnected }

enum FingerDetection { checking, detected, notDetected }

enum SignalQuality { checking, poor, fair, good }

enum BaselineStatus { notStarted, measuring, completed, failed }

/// Whether the user looked calm (per the camera) while the baseline was taken.
/// [unknown] when no clear face was seen (e.g. camera off / on the emulator).
enum BaselineCalmness { unknown, calm, notCalm }

enum StorageStatus { checking, ready, unavailable }

enum NetStatus { online, offline }

enum AiStatus { available, offline, error }

enum OverallStatus { checking, actionRequired, ready }

/// How a check should appear: a status [text], its [level] (icon/colour), and an
/// optional inline [message] shown only when there's a problem.
typedef CheckView = ({String text, CheckLevel level, String? message});

/// The required preparation-checklist items (all must be ticked to start).
const List<({String key, String label})> kPrepItems = [
  (key: 'seated', label: 'I am seated and ready.'),
  (key: 'face', label: 'My face is clearly visible.'),
  (key: 'finger', label: 'My finger is placed correctly on the sensor.'),
  (key: 'still', label: 'I have remained still for the baseline measurement.'),
  (
    key: 'disclaimer',
    label: 'I understand that this system is for wellness monitoring and is '
        'not a medical diagnosis.'
  ),
];

/// The full readiness state. Mutable so the controller can update individual
/// checks; the UI reads the computed booleans + [canStartSession].
class SessionReadiness {
  CameraPermission cameraPermission;
  CameraConnection cameraConnection;
  FaceVisibility faceVisibility;

  SensorConnection sensorConnection;
  FingerDetection fingerDetection;
  SignalQuality signalQuality;

  BaselineStatus baselineStatus;
  int? baselineBpm;
  int? currentBpm;
  double baselineProgress; // 0..1
  BaselineCalmness baselineCalmness;

  /// The user's personal resting BPM (median of their recent baselines), or null
  /// when there isn't enough history yet. When present it personalises the
  /// "elevated baseline" check instead of the fixed [restingBaselineCeiling].
  int? personalRestingBpm;

  /// How many past baselines the [personalRestingBpm] was derived from.
  int personalBaselineCount;

  StorageStatus storage;
  NetStatus internet;
  AiStatus aiService;

  /// When false, the user opted out of the heart-rate sensor (camera-only
  /// session): sensor + baseline checks are skipped and don't block starting.
  bool useSensor;

  Set<String> prepConfirmed;

  SessionReadiness({
    this.useSensor = true,
    this.cameraPermission = CameraPermission.checking,
    this.cameraConnection = CameraConnection.checking,
    this.faceVisibility = FaceVisibility.checking,
    this.sensorConnection = SensorConnection.checking,
    this.fingerDetection = FingerDetection.checking,
    this.signalQuality = SignalQuality.checking,
    this.baselineStatus = BaselineStatus.notStarted,
    this.baselineBpm,
    this.currentBpm,
    this.baselineProgress = 0,
    this.baselineCalmness = BaselineCalmness.unknown,
    this.personalRestingBpm,
    this.personalBaselineCount = 0,
    this.storage = StorageStatus.checking,
    this.internet = NetStatus.online,
    this.aiService = AiStatus.available,
    Set<String>? prepConfirmed,
  }) : prepConfirmed = prepConfirmed ?? <String>{};

  // ---- Mandatory checks (model field names per spec) ----------------------
  bool get cameraPermissionReady => cameraPermission == CameraPermission.granted;
  bool get cameraConnected => cameraConnection == CameraConnection.connected;
  bool get faceVisible => faceVisibility == FaceVisibility.detected;
  bool get sensorConnected => sensorConnection == SensorConnection.connected;
  bool get fingerDetected => fingerDetection == FingerDetection.detected;
  bool get signalQualityOk =>
      signalQuality == SignalQuality.good || signalQuality == SignalQuality.fair;
  bool get baselineCompleted => baselineStatus == BaselineStatus.completed;
  bool get storageReady => storage == StorageStatus.ready;

  // ---- Optional (do NOT block starting) -----------------------------------
  bool get internetAvailable => internet == NetStatus.online;
  bool get aiServiceAvailable => aiService == AiStatus.available;

  /// Poor signal no longer blocks the session (it's common on the emulator and
  /// on a briefly unstable real sensor) — it's surfaced as a warning instead, so
  /// the user can choose to continue.
  bool get signalQualityWarning =>
      useSensor && signalQuality == SignalQuality.poor;

  /// A missing baseline (failed or never captured) is likewise non-blocking: the
  /// session can run without it (the live insights just can't compare against a
  /// resting BPM). Surfaced as a warning the user can override.
  bool get baselineWarning =>
      useSensor &&
      (baselineStatus == BaselineStatus.failed ||
          baselineStatus == BaselineStatus.notStarted);

  /// Fallback ceiling used only when we have no personal history: above this a
  /// captured baseline is unlikely to be a true *resting* rate. (A typical adult
  /// resting HR is ~60–90 BPM.)
  static const int restingBaselineCeiling = 90;

  /// How far above the user's personal resting median still counts as "fine"
  /// (day-to-day variation + measurement noise) before we flag it as elevated.
  static const int personalElevatedMargin = 10;

  /// Minimum past baselines needed before we trust a personal resting median.
  static const int minPersonalBaselines = 3;

  /// Median of the user's past baselines, or null when there aren't enough to
  /// trust. Pure so it's easy to unit-test.
  static int? personalMedianFrom(List<int> baselines) {
    final valid = baselines.where((b) => b > 0).toList()..sort();
    if (valid.length < minPersonalBaselines) return null;
    return valid[valid.length ~/ 2];
  }

  /// The BPM above which today's baseline is treated as elevated: personalised
  /// to the user when we have history, otherwise the fixed ceiling. This both
  /// catches a tense baseline for a low-resting-HR user AND avoids nagging a
  /// user whose true resting rate is naturally high.
  int get elevatedBaselineThreshold => personalRestingBpm != null
      ? personalRestingBpm! + personalElevatedMargin
      : restingBaselineCeiling;

  /// True when a completed baseline looks too high to be a resting rate.
  bool get baselineLooksElevated =>
      useSensor &&
      baselineStatus == BaselineStatus.completed &&
      baselineBpm != null &&
      baselineBpm! > elevatedBaselineThreshold;

  /// True when the camera saw the user looking agitated (not calm) during the
  /// baseline — the resting reading is then likely too high. Non-blocking; we
  /// suggest re-measuring once calm. (Falls back to [baselineLooksElevated] when
  /// no face was seen, e.g. camera off / emulator.)
  bool get baselineNotCalm =>
      useSensor &&
      baselineStatus == BaselineStatus.completed &&
      baselineCalmness == BaselineCalmness.notCalm;

  /// Checklist items required for the current mode (finger + baseline items are
  /// dropped in camera-only mode).
  List<({String key, String label})> get requiredPrepItems => useSensor
      ? kPrepItems
      : kPrepItems
          .where((i) => i.key != 'finger' && i.key != 'still')
          .toList();

  bool get preparationConfirmed =>
      requiredPrepItems.every((i) => prepConfirmed.contains(i.key));

  /// Sensor checks, only relevant when [useSensor] is on.
  ///
  /// Only the sensor connection and a detected finger are mandatory. Signal
  /// quality and the baseline are intentionally NOT required — each only
  /// produces an overridable warning ([signalQualityWarning] / [baselineWarning]),
  /// since both are unavoidable on the emulator and common with a real sensor.
  bool get _sensorReady => sensorConnected && fingerDetected;

  /// True only when every mandatory check passes and the checklist is complete.
  /// Internet and AI availability are intentionally excluded; the heart-rate
  /// sensor + baseline are only required when [useSensor] is on.
  bool get canStartSession =>
      cameraPermissionReady &&
      cameraConnected &&
      faceVisible &&
      (!useSensor || _sensorReady) &&
      storageReady &&
      preparationConfirmed;

  bool get _anyChecking {
    if (cameraPermission == CameraPermission.checking ||
        cameraConnection == CameraConnection.checking ||
        faceVisibility == FaceVisibility.checking ||
        storage == StorageStatus.checking) {
      return true;
    }
    if (useSensor &&
        (sensorConnection == SensorConnection.checking ||
            fingerDetection == FingerDetection.checking ||
            signalQuality == SignalQuality.checking ||
            baselineStatus == BaselineStatus.measuring)) {
      return true;
    }
    return false;
  }

  OverallStatus get overall {
    if (_anyChecking) return OverallStatus.checking;
    // Ignoring the (optional) checklist, are all the device checks green?
    final devicesReady = cameraPermissionReady &&
        cameraConnected &&
        faceVisible &&
        (!useSensor || _sensorReady) &&
        storageReady;
    return devicesReady ? OverallStatus.ready : OverallStatus.actionRequired;
  }

  void togglePrep(String key, bool value) {
    if (value) {
      prepConfirmed.add(key);
    } else {
      prepConfirmed.remove(key);
    }
  }
}

/// Centralised display text + severity for each check, so widgets stay thin.
abstract final class ReadinessView {
  static CheckView cameraPermission(CameraPermission s) => switch (s) {
        CameraPermission.checking => (text: 'Checking', level: CheckLevel.checking, message: null),
        CameraPermission.granted => (text: 'Granted', level: CheckLevel.ok, message: null),
        CameraPermission.denied => (
            text: 'Permission Denied',
            level: CheckLevel.error,
            message: 'Camera permission is required for facial-emotion detection.'
          ),
      };

  static CheckView cameraConnection(CameraConnection s) => switch (s) {
        CameraConnection.checking => (text: 'Checking', level: CheckLevel.checking, message: null),
        CameraConnection.connected => (text: 'Connected', level: CheckLevel.ok, message: null),
        CameraConnection.unavailable => (
            text: 'Unavailable',
            level: CheckLevel.error,
            message: 'The camera is unavailable or currently being used by another application.'
          ),
      };

  static CheckView faceVisibility(FaceVisibility s) => switch (s) {
        FaceVisibility.checking => (text: 'Checking', level: CheckLevel.checking, message: null),
        FaceVisibility.detected => (text: 'Face Detected', level: CheckLevel.ok, message: null),
        FaceVisibility.notVisible => (
            text: 'Face Not Visible',
            level: CheckLevel.error,
            message: 'Position your face inside the guide and ensure sufficient lighting.'
          ),
        FaceVisibility.poorLighting => (
            text: 'Poor Lighting',
            level: CheckLevel.error,
            message: 'Position your face inside the guide and ensure sufficient lighting.'
          ),
        FaceVisibility.multipleFaces => (
            text: 'Multiple Faces Detected',
            level: CheckLevel.error,
            message: 'Only one clearly visible face is allowed. Make sure you are alone in frame.'
          ),
      };

  static CheckView sensorConnection(SensorConnection s) => switch (s) {
        SensorConnection.checking => (text: 'Checking', level: CheckLevel.checking, message: null),
        SensorConnection.connected => (text: 'Connected', level: CheckLevel.ok, message: null),
        SensorConnection.disconnected => (
            text: 'Disconnected',
            level: CheckLevel.error,
            message: 'Heart-rate sensor disconnected. Please reconnect the device before continuing.'
          ),
      };

  static CheckView fingerDetection(FingerDetection s) => switch (s) {
        FingerDetection.checking => (text: 'Checking', level: CheckLevel.checking, message: null),
        FingerDetection.detected => (text: 'Finger Detected', level: CheckLevel.ok, message: null),
        FingerDetection.notDetected => (
            text: 'No Finger Detected',
            level: CheckLevel.error,
            message: 'Place your finger gently on the heart-rate sensor and keep it still.'
          ),
      };

  static CheckView signalQuality(SignalQuality s) => switch (s) {
        SignalQuality.checking => (text: 'Checking', level: CheckLevel.checking, message: null),
        SignalQuality.good => (text: 'Good', level: CheckLevel.ok, message: null),
        SignalQuality.fair => (text: 'Fair', level: CheckLevel.warn, message: null),
        SignalQuality.poor => (
            text: 'Poor',
            level: CheckLevel.warn,
            message: 'Signal is unstable — for a cleaner reading adjust your finger and stay still. '
                'You can still start the session; this won\'t block you.'
          ),
      };

  static CheckView storage(StorageStatus s) => switch (s) {
        StorageStatus.checking => (text: 'Checking', level: CheckLevel.checking, message: null),
        StorageStatus.ready => (text: 'Ready', level: CheckLevel.ok, message: null),
        StorageStatus.unavailable => (
            text: 'Unavailable',
            level: CheckLevel.error,
            message: 'The system cannot save your session data. Please try again.'
          ),
      };

  static CheckView aiService(AiStatus s) => switch (s) {
        AiStatus.available => (text: 'Available', level: CheckLevel.ok, message: null),
        AiStatus.offline => (
            text: 'Offline',
            level: CheckLevel.warn,
            message: 'The session can continue. Your AI summary will be generated later when the service becomes available.'
          ),
        AiStatus.error => (
            text: 'Error',
            level: CheckLevel.warn,
            message: 'The session can continue. Your AI summary will be generated later when the service becomes available.'
          ),
      };
}
