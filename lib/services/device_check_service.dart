import 'package:camera/camera.dart';

import '../models/session_readiness.dart';
import 'ai_config.dart';
import 'sensor_filter.dart';
import 'sensor_service.dart';
import 'supabase_service.dart';

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
    return (
      permission: hasCamera ? CameraPermission.granted : CameraPermission.denied,
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
      ai: AiConfig.hasKey ? AiStatus.available : AiStatus.offline,
    );
  }
}

/// Deterministic checks for tests / demos without hardware. All fields default
/// to "ready"; override any of them to exercise failure paths.
class MockDeviceCheckService implements DeviceCheckService {
  final CameraSnapshot camera;
  final SensorSnapshot sensor;
  final SystemSnapshot system;
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
    this.delay = Duration.zero,
  });

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
