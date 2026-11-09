import 'package:shared_preferences/shared_preferences.dart';

/// How the app talks to the ESP32 sensor.
/// - [wifi]: the legacy SoftAP/HTTP transport.
/// - [ble]: Bluetooth LE — coexists with normal Wi-Fi so the phone keeps its
///   internet while reading the sensor (physical phone only; no emulator).
/// - [simulated]: fake readings, no hardware — for demos/dev on the emulator
///   where real Wi-Fi/Bluetooth sensors can't connect.
enum SensorTransport { wifi, ble, simulated }

/// Holds the ESP32 sensor address and the chosen transport. For Wi-Fi the user
/// sets the IP shown on the Serial Monitor; for BLE we remember the last
/// connected device so we can reconnect to it directly.
class SensorConfig {
  static const _key = 'esp32_base_url';
  static const _transportKey = 'sensor_transport';
  static const _bleIdKey = 'sensor_ble_device_id';
  static const _bleNameKey = 'sensor_ble_device_name';
  static const defaultBaseUrl = 'http://192.168.4.1'; // legacy SoftAP fallback

  String baseUrl = defaultBaseUrl;
  SensorTransport transport = SensorTransport.wifi;
  String? bleDeviceId;
  String? bleDeviceName;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    baseUrl = prefs.getString(_key) ?? defaultBaseUrl;
    final t = prefs.getString(_transportKey);
    transport = SensorTransport.values.firstWhere(
      (e) => e.name == t,
      orElse: () => SensorTransport.wifi,
    );
    bleDeviceId = prefs.getString(_bleIdKey);
    bleDeviceName = prefs.getString(_bleNameKey);
  }

  Future<void> setTransport(SensorTransport t) async {
    transport = t;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_transportKey, t.name);
  }

  /// Remembers the last BLE device that connected, so future scans can prefer
  /// it.
  Future<void> setBleDevice({required String id, String? name}) async {
    bleDeviceId = id;
    bleDeviceName = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_bleIdKey, id);
    if (name != null && name.isNotEmpty) {
      await prefs.setString(_bleNameKey, name);
    }
  }

  /// Accepts an IP, host, or full URL and stores a normalized `http://host`.
  Future<void> setFromInput(String input) async {
    baseUrl = _normalize(input);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, baseUrl);
  }

  /// Host without the scheme, for showing in the settings field.
  String get hostForDisplay =>
      baseUrl.replaceFirst('http://', '').replaceFirst('https://', '');

  /// Normalizes input to `http://host` WITHOUT persisting it — used to test an
  /// address before the user commits to saving it.
  String normalize(String input) => _normalize(input);

  String _normalize(String input) {
    var v = input.trim();
    if (v.isEmpty) return defaultBaseUrl;
    if (!v.startsWith('http://') && !v.startsWith('https://')) {
      v = 'http://$v';
    }
    if (v.endsWith('/')) v = v.substring(0, v.length - 1);
    return v;
  }
}

final sensorConfig = SensorConfig();
