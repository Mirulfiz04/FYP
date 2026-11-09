import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sensor_config.dart';
import 'sensor_service.dart';

enum DeviceConnState { disconnected, connecting, connected, failed }

/// Owns the heart-rate sensor (ESP32 / MAX30102) connection state for the
/// Connected Devices screen. Keeps device logic out of the UI. Does NOT expose
/// live heart-rate values for the profile area beyond a one-off connectivity
/// probe.
class DeviceConnectionController extends ChangeNotifier {
  static const _lastConnectedKey = 'device_last_connected';

  DeviceConnState _state = DeviceConnState.disconnected;
  String _detail = 'Not connected yet.';
  DateTime? _lastConnected;

  DeviceConnState get state => _state;
  String get detail => _detail;
  DateTime? get lastConnected => _lastConnected;

  String get deviceName => 'MAX30102 heart-rate sensor';
  String get connectionMethod => switch (sensorConfig.transport) {
        SensorTransport.ble => 'Bluetooth LE · ESP32',
        SensorTransport.simulated => 'Simulated sensor (no hardware)',
        SensorTransport.wifi => 'Wi-Fi · ESP32 SoftAP',
      };
  String get address => switch (sensorConfig.transport) {
        SensorTransport.ble =>
          sensorConfig.bleDeviceName ?? sensorConfig.bleDeviceId ?? 'MEDS_ESP32',
        SensorTransport.simulated => 'Simulated',
        SensorTransport.wifi => sensorConfig.hostForDisplay,
      };

  Future<void> loadLast() async {
    final prefs = await SharedPreferences.getInstance();
    final iso = prefs.getString(_lastConnectedKey);
    if (iso != null) _lastConnected = DateTime.tryParse(iso);
    notifyListeners();
  }

  /// Saves [address] (when provided) then probes the sensor. Updates state to
  /// connecting → connected | failed.
  Future<void> connect({String? address}) async {
    // The address field only applies to the Wi-Fi transport (it's an IP/host).
    if (sensorConfig.transport == SensorTransport.wifi &&
        address != null &&
        address.trim().isNotEmpty) {
      await sensorConfig.setFromInput(address);
    }
    _state = DeviceConnState.connecting;
    _detail = 'Connecting to ${this.address}…';
    notifyListeners();

    try {
      final reading = await createSensorService(
        timeout: const Duration(seconds: 5),
      ).fetchReading();
      _state = DeviceConnState.connected;
      _detail = reading.hr > 0
          ? 'Connected · pulse detected'
          : 'Connected · place a finger on the sensor';
      _lastConnected = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastConnectedKey, _lastConnected!.toIso8601String());
    } catch (e) {
      _state = DeviceConnState.failed;
      _detail = _friendlyError(e);
    }
    notifyListeners();
  }

  Future<void> retry() => connect();

  void disconnect() {
    _state = DeviceConnState.disconnected;
    _detail = 'Disconnected.';
    notifyListeners();
  }

  String _friendlyError(Object e) {
    final s = e.toString();
    if (sensorConfig.transport == SensorTransport.ble) {
      if (s.contains('not available') || s.contains('not supported')) {
        return 'Bluetooth unavailable. BLE does not work on the emulator — '
            'use a physical phone.';
      }
      if (s.contains('find') || s.contains('TimeoutException')) {
        return 'Could not find MEDS_ESP32. Make sure the ESP32 is powered and '
            'Bluetooth is on.';
      }
      return 'Could not reach the sensor over Bluetooth.';
    }
    if (s.contains('TimeoutException')) {
      return 'Timed out. Join the MEDS_ESP32 Wi-Fi and check the address.';
    }
    if (s.contains('SocketException') || s.contains('Failed host lookup')) {
      return 'No route to the sensor. Join the MEDS_ESP32 Wi-Fi.';
    }
    return 'Could not reach the sensor.';
  }
}
