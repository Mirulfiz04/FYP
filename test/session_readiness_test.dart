import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meds_flutter_no_python/models/session_readiness.dart';
import 'package:meds_flutter_no_python/services/baseline_history_service.dart';
import 'package:meds_flutter_no_python/services/baseline_measurement_service.dart';
import 'package:meds_flutter_no_python/services/device_check_service.dart';
import 'package:meds_flutter_no_python/viewmodels/session_readiness_controller.dart';
import 'package:meds_flutter_no_python/widgets/meds_bottom_bar.dart';

SessionReadinessController ctrl({
  DeviceCheckService? device,
  BaselineMeasurementService? baseline,
  BaselineHistoryService? history,
}) =>
    SessionReadinessController(
      deviceService: device ?? MockDeviceCheckService(),
      baselineService: baseline ?? const MockBaselineMeasurementService(),
      historyService: history,
    );

Future<void> fullyReady(SessionReadinessController c) async {
  await c.runChecks();
  await c.measureBaseline();
  for (final item in kPrepItems) {
    c.togglePrep(item.key, true);
  }
}

void main() {
  test('1. all checks pass + baseline + checklist → can start', () async {
    final c = ctrl();
    await fullyReady(c);
    expect(c.state.overall, OverallStatus.ready);
    expect(c.canStart, isTrue);
  });

  test('2. denied camera permission blocks start', () async {
    final c = ctrl(
      device: MockDeviceCheckService(
        camera: (
          permission: CameraPermission.denied,
          connection: CameraConnection.connected,
          face: FaceVisibility.detected,
        ),
      ),
    );
    await fullyReady(c);
    expect(c.state.cameraPermissionReady, isFalse);
    expect(c.canStart, isFalse);
    expect(c.state.overall, OverallStatus.actionRequired);
  });

  test('3. disconnected sensor blocks start', () async {
    final c = ctrl(
      device: MockDeviceCheckService(
        sensor: (
          connection: SensorConnection.disconnected,
          finger: FingerDetection.notDetected,
          signal: SignalQuality.poor,
          bpm: null,
        ),
      ),
    );
    await fullyReady(c);
    expect(c.canStart, isFalse);
  });

  test('4. poor signal quality warns but does NOT block start', () async {
    final c = ctrl(
      device: MockDeviceCheckService(
        sensor: (
          connection: SensorConnection.connected,
          finger: FingerDetection.detected,
          signal: SignalQuality.poor,
          bpm: 80,
        ),
      ),
    );
    await fullyReady(c);
    expect(c.state.signalQualityOk, isFalse);
    expect(c.state.signalQualityWarning, isTrue);
    expect(c.canStart, isTrue);
  });

  test('5. internet + AI offline do NOT block start', () async {
    final c = ctrl(
      device: MockDeviceCheckService(
        system: (
          storage: StorageStatus.ready,
          internet: NetStatus.offline,
          ai: AiStatus.offline,
        ),
      ),
    );
    await fullyReady(c);
    expect(c.state.aiServiceAvailable, isFalse);
    expect(c.state.internetAvailable, isFalse);
    expect(c.canStart, isTrue);
  });

  test('6. storage unavailable blocks start', () async {
    final c = ctrl(
      device: MockDeviceCheckService(
        system: (
          storage: StorageStatus.unavailable,
          internet: NetStatus.online,
          ai: AiStatus.available,
        ),
      ),
    );
    await fullyReady(c);
    expect(c.canStart, isFalse);
  });

  test('7. baseline measurement completes and stores BPM', () async {
    final c = ctrl(baseline: const MockBaselineMeasurementService(bpm: 74));
    await c.runChecks();
    await c.measureBaseline();
    expect(c.state.baselineStatus, BaselineStatus.completed);
    expect(c.state.baselineBpm, 74);
  });

  test('8. failed baseline warns but does NOT block start', () async {
    final c = ctrl(baseline: const MockBaselineMeasurementService(succeed: false));
    await c.runChecks();
    await c.measureBaseline();
    for (final item in kPrepItems) {
      c.togglePrep(item.key, true);
    }
    expect(c.state.baselineCompleted, isFalse);
    expect(c.state.baselineWarning, isTrue);
    expect(c.canStart, isTrue);
  });

  test('9. preparation checklist is required', () async {
    final c = ctrl();
    await c.runChecks();
    await c.measureBaseline();
    expect(c.canStart, isFalse); // nothing ticked yet
    for (final item in kPrepItems) {
      c.togglePrep(item.key, true);
    }
    expect(c.canStart, isTrue);
    c.togglePrep('seated', false);
    expect(c.canStart, isFalse);
  });

  testWidgets('10. bottom bar shows the Live flow active (no list tab lit)',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        bottomNavigationBar: MedsBottomBar(index: -1, onSelect: (_) {}),
      ),
    ));
    for (final label in ['Home', 'History', 'Insights', 'Profile']) {
      final t = tester.widget<Text>(find.text(label));
      expect(t.style?.color, medsNavMuted);
    }
  });

  test('12. a not-calm baseline warns but does NOT block start', () async {
    final c = ctrl(
      baseline: const MockBaselineMeasurementService(
        bpm: 78,
        calmness: BaselineCalmness.notCalm,
      ),
    );
    await fullyReady(c);
    expect(c.state.baselineCompleted, isTrue);
    expect(c.state.baselineNotCalm, isTrue);
    expect(c.canStart, isTrue);
  });

  test('13. an elevated baseline (high BPM) is flagged but does NOT block',
      () async {
    final c = ctrl(baseline: const MockBaselineMeasurementService(bpm: 110));
    await fullyReady(c);
    expect(c.state.baselineLooksElevated, isTrue);
    expect(c.canStart, isTrue);
  });

  test('14. a calm, normal baseline raises no baseline warnings', () async {
    final c = ctrl(
      baseline: const MockBaselineMeasurementService(
        bpm: 72,
        calmness: BaselineCalmness.calm,
      ),
    );
    await fullyReady(c);
    expect(c.state.baselineNotCalm, isFalse);
    expect(c.state.baselineLooksElevated, isFalse);
    expect(c.state.baselineWarning, isFalse);
    expect(c.canStart, isTrue);
  });

  group('personal baseline (history-aware elevated check)', () {
    test('15. median of recent baselines becomes the personal resting rate',
        () async {
      final c = ctrl(history: const MockBaselineHistoryService([70, 72, 68, 74]));
      await c.loadPersonalBaseline();
      expect(c.state.personalRestingBpm, 72); // median of [68,70,72,74]
      expect(c.state.personalBaselineCount, 4);
    });

    test('16. too little history → no personal rate, fixed ceiling used',
        () async {
      final c = ctrl(history: const MockBaselineHistoryService([70, 72]));
      await c.loadPersonalBaseline();
      expect(c.state.personalRestingBpm, isNull);
      expect(c.state.elevatedBaselineThreshold,
          SessionReadiness.restingBaselineCeiling);
    });

    test('17. 85 BPM is flagged elevated for a low-resting (≈70) user',
        () async {
      final c = ctrl(
        baseline: const MockBaselineMeasurementService(bpm: 85),
        history: const MockBaselineHistoryService([68, 70, 72, 70]),
      );
      await c.loadPersonalBaseline();
      await fullyReady(c);
      // 85 < fixed 90 (old rule would NOT flag) but > 70 + margin(10) = 80.
      expect(c.state.personalRestingBpm, 70);
      expect(c.state.baselineLooksElevated, isTrue);
      expect(c.canStart, isTrue);
    });

    test('18. 95 BPM is NOT flagged for a naturally high-resting (≈92) user',
        () async {
      final c = ctrl(
        baseline: const MockBaselineMeasurementService(bpm: 95),
        history: const MockBaselineHistoryService([90, 92, 94, 92]),
      );
      await c.loadPersonalBaseline();
      await fullyReady(c);
      // 95 > fixed 90 (old rule WOULD nag) but < 92 + margin(10) = 102.
      expect(c.state.personalRestingBpm, 92);
      expect(c.state.baselineLooksElevated, isFalse);
      expect(c.canStart, isTrue);
    });
  });

  test('11. camera-only mode lets the session start without the sensor', () async {
    final c = ctrl(
      device: MockDeviceCheckService(
        sensor: (
          connection: SensorConnection.disconnected,
          finger: FingerDetection.notDetected,
          signal: SignalQuality.poor,
          bpm: null,
        ),
      ),
    );
    c.setUseSensor(false);
    await c.runChecks();
    // Camera-only drops the finger + baseline checklist items.
    expect(c.state.requiredPrepItems.length, 3);
    for (final item in c.state.requiredPrepItems) {
      c.togglePrep(item.key, true);
    }
    // Sensor disconnected + no baseline, but ignored in camera-only mode.
    expect(c.canStart, isTrue);
  });
}
