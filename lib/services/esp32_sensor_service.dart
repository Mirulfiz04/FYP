import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:http/http.dart' as http;
import '../models/sensor_reading.dart';
import 'sensor_config.dart';
import 'sensor_service.dart';
import 'wifi_sensor_channel.dart';

class Esp32SensorService implements SensorService {
  final String baseUrl;
  final Duration timeout;

  Esp32SensorService({
    String? baseUrl,
    this.timeout = const Duration(seconds: 2),
  }) : baseUrl = baseUrl ?? sensorConfig.baseUrl;

  @override
  Future<RawSensorReading> fetchReading() async {
    final body = await _fetchBody('$baseUrl/data');
    final jsonMap = json.decode(body) as Map<String, dynamic>;
    return RawSensorReading.fromJson(jsonMap);
  }

  /// Gets the raw response body from the sensor.
  ///
  /// On Android we first try the native Wi-Fi-pinned fetch so the request
  /// reaches the ESP32 hotspot even when mobile data is the default network. If
  /// that path isn't available or fails (e.g. older build, emulator, or the
  /// phone isn't on Wi-Fi) we fall back to a normal HTTP GET on the default
  /// route — so behaviour is never worse than before.
  Future<String> _fetchBody(String url) async {
    if (Platform.isAndroid) {
      try {
        return await WifiSensorChannel.fetchOverWifi(url, timeout: timeout);
      } catch (_) {
        // Fall through to the default-route HTTP request below.
      }
    }

    final response = await http.get(Uri.parse(url)).timeout(timeout);
    if (response.statusCode != 200) {
      throw Exception('ESP32 HTTP ${response.statusCode}');
    }
    return response.body;
  }
}
