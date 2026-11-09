import 'package:flutter/services.dart';

/// Bridge to the native (Android) helper that fetches a URL over the Wi-Fi
/// transport specifically. Used for the ESP32 sensor so its request reaches the
/// MEDS_ESP32 hotspot even when mobile data is the default (internet) network.
class WifiSensorChannel {
  static const MethodChannel _channel = MethodChannel('meds/wifi_sensor');

  /// Performs a GET on [url] pinned to the Wi-Fi network and returns the raw
  /// response body. Throws [PlatformException] (codes: NO_WIFI / HTTP / FETCH)
  /// on failure, or [MissingPluginException] if the native side isn't present
  /// (e.g. an older build or a non-Android platform).
  static Future<String> fetchOverWifi(
    String url, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final body = await _channel.invokeMethod<String>('fetchOverWifi', {
      'url': url,
      'timeoutMs': timeout.inMilliseconds,
    });
    if (body == null || body.isEmpty) {
      throw Exception('Empty response from sensor');
    }
    return body;
  }
}
