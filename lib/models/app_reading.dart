import 'emotion_result.dart';
import 'sensor_reading.dart';

class AppReading {
  final EmotionResult emotion;
  final ProcessedSensorReading sensor;
  final DateTime timestamp;

  const AppReading({
    required this.emotion,
    required this.sensor,
    required this.timestamp,
  });
}
