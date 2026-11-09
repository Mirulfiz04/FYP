import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/app_notification.dart';

/// The ONLY file that imports `flutter_local_notifications`. Everything else
/// talks to OS notifications through [NotificationService.push] (a [PushFn]),
/// so the rest of the app stays decoupled from the plugin and unit-testable.
///
/// Setup required after adding the package:
///   1. `flutter pub get`
///   2. Android 13+ runtime permission is requested via [requestPermission].
///      The POST_NOTIFICATIONS permission line is added to AndroidManifest.xml.
///   3. Uses the existing launcher icon (`@mipmap/ic_launcher`) — no extra
///      asset needed.
class LocalNotifications {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const _channelId = 'meds_default';
  static const _channelName = 'MEDS notifications';
  static const _channelDesc =
      'Session, AI insight and wellbeing-trend notifications.';

  static bool _initialized = false;

  /// Initializes the plugin. [onSelect] is called with the tapped
  /// notification's deep-link payload when the app is in the foreground or
  /// background (not terminated).
  static Future<void> init({
    void Function(String? deepLink)? onSelect,
  }) async {
    if (_initialized) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (response) =>
          onSelect?.call(response.payload),
      onDidReceiveBackgroundNotificationResponse: _onBackgroundResponse,
    );

    // Create the Android channel up-front so importance is correct.
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDesc,
            importance: Importance.high,
          ),
        );

    _initialized = true;
  }

  /// Requests OS notification permission (Android 13+, iOS). Returns true when
  /// granted (or not required). Denials are handled gracefully by callers —
  /// in-app notifications still work without OS permission.
  static Future<bool> requestPermission() async {
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final androidGranted = await android?.requestNotificationsPermission();

      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final iosGranted = await ios?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );

      return androidGranted ?? iosGranted ?? true;
    } catch (e) {
      debugPrint('LocalNotifications.requestPermission failed: $e');
      return false;
    }
  }

  /// Shows an OS notification for [n], carrying its deep link as the payload.
  static Future<void> show(AppNotification n) async {
    if (!_initialized) return;
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );
    await _plugin.show(
      n.notificationId.hashCode & 0x7fffffff,
      n.title,
      n.message,
      details,
      payload: n.deepLink,
    );
  }

  /// If the app was launched by tapping a notification (terminated state),
  /// returns its deep-link payload so main can route after the first frame.
  static Future<String?> launchDeepLink() async {
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp ?? false) {
        return details?.notificationResponse?.payload;
      }
    } catch (_) {}
    return null;
  }
}

/// Background isolate tap handler. Cannot route (no app context); the reliable
/// terminated-tap path is [LocalNotifications.launchDeepLink] on next launch.
@pragma('vm:entry-point')
void _onBackgroundResponse(NotificationResponse response) {
  // Intentionally empty.
}
