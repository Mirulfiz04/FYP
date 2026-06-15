import 'package:shared_preferences/shared_preferences.dart';

/// Holds the ESP32 sensor address. With the ESP32 in Station mode it joins the
/// home Wi-Fi and gets a LAN IP (printed on its Serial Monitor); the user sets
/// that IP here so the phone can reach the sensor and the cloud at the same time.
class SensorConfig {
  static const _key = 'esp32_base_url';
  static const defaultBaseUrl = 'http://192.168.4.1'; // legacy SoftAP fallback

  String baseUrl = defaultBaseUrl;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    baseUrl = prefs.getString(_key) ?? defaultBaseUrl;
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
