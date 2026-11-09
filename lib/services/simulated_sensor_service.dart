import 'dart:math';

import '../models/sensor_reading.dart';
import 'sensor_service.dart';

/// Fake sensor backend for development/demos with no hardware — handy on the
/// Android emulator, where real Wi-Fi/Bluetooth sensors can't connect.
///
/// It produces believable readings that pass [SensorFilter] as GOOD: a heart
/// rate that random-walks inside a resting range, near-constant IR/RED (so the
/// signal-stability check holds), and a plausible SpO₂. Everything downstream
/// (live session, baseline, charts, AI insights) then behaves as if a real
/// sensor were attached.
///
/// A singleton so the heart rate drifts continuously across calls instead of
/// jumping each time a new instance is made.
class SimulatedSensorService implements SensorService {
  SimulatedSensorService._();
  static final SimulatedSensorService instance = SimulatedSensorService._();

  final Random _rng = Random();
  int _hr = 72; // starts in the filter's first-sample window (50..100)

  @override
  Future<RawSensorReading> fetchReading() async {
    // Small random walk, kept well inside the filter's jump limits so it stays
    // "stable" and reads as GOOD rather than being rejected as a spike.
    _hr += _rng.nextInt(3) - 1; // -1, 0, or +1
    if (_hr < 62) _hr = 62;
    if (_hr > 88) _hr = 88;

    final spo2 = 97 + _rng.nextInt(3); // 97..99
    // Near-constant IR/RED (tiny noise) so _isSignalStable stays true.
    final ir = 100000 + _rng.nextInt(1500);
    final red = 95000 + _rng.nextInt(1500);

    return RawSensorReading(
      hr: _hr,
      hrValid: 1,
      spo2: spo2,
      spo2Valid: 1,
      ir: ir,
      red: red,
      algoHr: _hr,
      instantHr: _hr,
      rateCount: 8,
      status: 'measuring',
    );
  }
}
