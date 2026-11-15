import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../models/session_readiness.dart';
import 'sensor_filter.dart';
import 'sensor_service.dart';
import 'supabase_service.dart';
import 'voice_classifier.dart';

typedef CameraSnapshot = ({
  CameraPermission permission,
  CameraConnection connection,
  FaceVisibility face,
});
typedef SensorSnapshot = ({
  SensorConnection connection,
  FingerDetection finger,
  SignalQuality signal,
  int? bpm,
});
typedef VoiceSnapshot = ({MicPermission mic, VoiceModelStatus model});
typedef SystemSnapshot = ({
  StorageStatus storage,
  NetStatus internet,
  AiStatus ai,
});

/// Runs the pre-flight device checks. Grouped so each subsystem is probed once.
/// Swap [RealDeviceCheckService] for [MockDeviceCheckService] in tests / when
/// hardware isn't available.
abstract class DeviceCheckService {
  Future<CameraSnapshot> checkCamera();
  Future<SensorSnapshot> checkSensor();
  Future<SystemSnapshot> checkSystem();

  /// Microphone permission + whether the voice model loads on this device.
  Future<VoiceSnapshot> checkVoice();

  /// Records a short answer; true when something loud enough to be speech
  /// was heard.
  /// [onLevel] reports the live microphone level (0..1) while recording.
  Future<bool> testVoice({void Function(double level)? onLevel});
}

/// Real checks using the existing services. Note: true camera-permission and
/// live face detection require a running camera + classifier (done during the
/// live session); here camera availability is inferred from [cameras] and face
/// visibility is assumed ready — replace with a real preview check later.
class RealDeviceCheckService implements DeviceCheckService {
  final List<CameraDescription> cameras;
  RealDeviceCheckService(this.cameras);

  @override
  Future<CameraSnapshot> checkCamera() async {
    final hasCamera = cameras.isNotEmpty;
    var allowed = hasCamera;
    // Ask for the real permission on phones (this shows the system prompt the
    // first time). Other platforms keep the old "has a camera" inference.
    if (hasCamera &&
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      try {
        allowed = (await Permission.camera.request()).isGranted;
      } catch (_) {/* plugin unavailable: keep the inference */}
    }
    return (
      permission: allowed ? CameraPermission.granted : CameraPermission.denied,
      connection:
          hasCamera ? CameraConnection.connected : CameraConnection.unavailable,
      face: hasCamera ? FaceVisibility.detected : FaceVisibility.notVisible,
    );
  }

  @override
  Future<SensorSnapshot> checkSensor() async {
    try {
      final raw = await createSensorService(timeout: const Duration(seconds: 4))
          .fetchReading();
      final processed = SensorFilter().process(raw);
      final q = processed.sensorQuality;
      final noFinger = raw.status == 'no_finger' || q == 'NO FINGER';
      return (
        connection: SensorConnection.connected,
        finger: noFinger ? FingerDetection.notDetected : FingerDetection.detected,
        signal: switch (q) {
          'GOOD' || 'HOLDING HR' => SignalQuality.good,
          'WAITING' => SignalQuality.fair,
          _ => SignalQuality.poor,
        },
        bpm: processed.hr > 0 ? processed.hr : null,
      );
    } catch (_) {
      return (
        connection: SensorConnection.disconnected,
        finger: FingerDetection.notDetected,
        signal: SignalQuality.poor,
        bpm: null,
      );
    }
  }

  @override
  Future<VoiceSnapshot> checkVoice() async {
    var mic = MicPermission.denied;
    try {
      // Same call the live check-in uses; shows the system prompt first time.
      final recorder = AudioRecorder();
      if (await recorder.hasPermission()) mic = MicPermission.granted;
      await recorder.dispose();
    } catch (_) {/* no recorder on this platform: stays denied */}
    var model = VoiceModelStatus.missing;
    final voice = VoiceClassifier();
    try {
      await voice.load();
      if (voice.labels.isNotEmpty) model = VoiceModelStatus.ready;
    } catch (_) {/* model not bundled / not loadable */} finally {
      voice.close();
    }
    return (mic: mic, model: model);
  }

  @override
  Future<bool> testVoice({void Function(double level)? onLevel}) async {
    final voice = VoiceClassifier();
    try {
      final audio = await voice.record(onLevel: onLevel);
      return audio != null &&
          VoiceClassifier.trimSilence(audio,
                  minRms: VoiceClassifier.minSpeechRms)
              .isNotEmpty;
    } finally {
      voice.close();
    }
  }

  @override
  Future<SystemSnapshot> checkSystem() async {
    StorageStatus storage;
    NetStatus internet;
    try {
      await SupabaseService().ping().timeout(const Duration(seconds: 6));
      storage = StorageStatus.ready;
      internet = NetStatus.online;
    } catch (_) {
      storage = StorageStatus.unavailable;
      internet = NetStatus.offline;
    }
    return (
      storage: storage,
      internet: internet,
      // AI runs through the Supabase Edge Function, so it needs Supabase.
      ai: internet == NetStatus.online ? AiStatus.available : AiStatus.offline,
    );
  }
}

/// Deterministic checks for tests / demos without hardware. All fields default
/// to "ready"; override any of them to exercise failure paths.
class MockDeviceCheckService implements DeviceCheckService {
  final CameraSnapshot camera;
  final SensorSnapshot sensor;
  final SystemSnapshot system;
  final VoiceSnapshot voice;
  final bool voiceHeard;
  final Duration delay;

  MockDeviceCheckService({
    this.camera = const (
      permission: CameraPermission.granted,
      connection: CameraConnection.connected,
      face: FaceVisibility.detected,
    ),
    this.sensor = const (
      connection: SensorConnection.connected,
      finger: FingerDetection.detected,
      signal: SignalQuality.good,
      bpm: 72,
    ),
    this.system = const (
      storage: StorageStatus.ready,
      internet: NetStatus.online,
      ai: AiStatus.available,
    ),
    this.voice = const (
      mic: MicPermission.granted,
      model: VoiceModelStatus.ready,
    ),
    this.voiceHeard = true,
    this.delay = Duration.zero,
  });

  @override
  Future<VoiceSnapshot> checkVoice() async => voice;

  @override
  Future<bool> testVoice({void Function(double level)? onLevel}) async {
    onLevel?.call(voiceHeard ? 0.6 : 0);
    return voiceHeard;
  }

  @override
  Future<CameraSnapshot> checkCamera() async {
    if (delay != Duration.zero) await Future.delayed(delay);
    return camera;
  }

  @override
  Future<SensorSnapshot> checkSensor() async {
    if (delay != Duration.zero) await Future.delayed(delay);
    return sensor;
  }

  @override
  Future<SystemSnapshot> checkSystem() async {
    if (delay != Duration.zero) await Future.delayed(delay);
    return system;
  }
}
