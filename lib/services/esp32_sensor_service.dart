import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/sensor_reading.dart';
import 'sensor_config.dart';

class Esp32SensorService {
  final String baseUrl;
  final Duration timeout;

  Esp32SensorService({
    String? baseUrl,
    this.timeout = const Duration(seconds: 2),
  }) : baseUrl = baseUrl ?? sensorConfig.baseUrl;

  Future<RawSensorReading> fetchReading() async {
    final uri = Uri.parse('$baseUrl/data');
    final response = await http.get(uri).timeout(timeout);

    if (response.statusCode != 200) {
      throw Exception('ESP32 HTTP ${response.statusCode}');
    }

    final jsonMap = json.decode(response.body) as Map<String, dynamic>;
    return RawSensorReading.fromJson(jsonMap);
  }
}
