import '../models/sensor_reading.dart';
import 'ble_sensor_service.dart';
import 'esp32_sensor_service.dart';
import 'sensor_config.dart';
import 'simulated_sensor_service.dart';

/// Transport-agnostic source of heart-rate readings. Both the Wi-Fi
/// ([Esp32SensorService]) and Bluetooth ([BleSensorService]) backends implement
/// this, so the rest of the app (live session, baseline, device checks) only
/// ever depends on [fetchReading] and never on the transport.
///
/// The contract is pull-based on purpose: BLE is push/notify under the hood, but
/// [BleSensorService] caches the latest notification and hands it back here, so
/// every existing 1-second polling loop keeps working without changes.
abstract class SensorService {
  Future<RawSensorReading> fetchReading();
}

/// Returns the sensor backend for the transport the user picked in Settings
/// ([SensorConfig.transport]).
///
/// Wi-Fi is created fresh per call (it's stateless request/response). BLE is a
/// long-lived connection, so the shared singleton is returned — never a new
/// scan/connect per reading.
SensorService createSensorService({Duration? timeout, String? baseUrl}) {
  switch (sensorConfig.transport) {
    case SensorTransport.ble:
      return BleSensorService.instance;
    case SensorTransport.simulated:
      return SimulatedSensorService.instance;
    case SensorTransport.wifi:
      return Esp32SensorService(
        baseUrl: baseUrl,
        timeout: timeout ?? const Duration(seconds: 2),
      );
  }
}
