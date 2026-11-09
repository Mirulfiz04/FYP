/// Generates the live-session insight text from simple local rules, so we never
/// call the AI API on every sensor update. These are monitoring insights, not a
/// medical diagnosis. Pure Dart → unit-testable.
abstract final class LiveInsightRules {
  static const String disclaimer =
      'Monitoring insight only — not a medical diagnosis.';

  static String evaluate({
    required bool faceVisible,
    required String sensorQuality,
    required int hr,
    required bool validBpm,
    int? baselineBpm,
  }) {
    if (!faceVisible) return 'Face is not clearly visible.';

    switch (sensorQuality) {
      case 'DISCONNECTED':
      case 'BAD SIGNAL':
        return 'Heart-rate signal is unstable.';
      case 'NO FINGER':
        return 'Place your finger correctly on the sensor.';
    }

    if (validBpm && baselineBpm != null && hr > baselineBpm + 15) {
      return 'Your heart rate is above your baseline.';
    }
    return 'Emotion and heart-rate readings are currently stable.';
  }
}
