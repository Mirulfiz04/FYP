import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_notification.dart';

/// User preferences for which notifications are allowed. Mirrors the pattern of
/// [themeController] / [sensorConfig]: a [ChangeNotifier] singleton, persisted
/// locally and (optionally) synced to the `profiles.notification_settings`
/// column when a backend sync function is wired in.
class NotificationPrefs extends ChangeNotifier {
  static const _key = 'notification_settings';

  bool sensorCamera;
  bool sessionCompleted;
  bool aiSummary;
  bool weeklyTrend;

  /// Optional backend sync hook (set from main once Supabase is available) so
  /// this file never imports Supabase directly. Best-effort; failures ignored.
  Future<void> Function(Map<String, dynamic> settings)? onSync;

  NotificationPrefs({
    this.sensorCamera = true,
    this.sessionCompleted = true,
    this.aiSummary = true,
    this.weeklyTrend = false, // default OFF per spec
  });

  /// True when notifications of [type]'s category are allowed.
  bool isEnabled(NotificationType type) => switch (type.category) {
        NotificationCategory.sensorCamera => sensorCamera,
        NotificationCategory.session => sessionCompleted,
        NotificationCategory.ai => aiSummary,
        NotificationCategory.trend => weeklyTrend,
      };

  Map<String, dynamic> toMap() => {
        'sensorCamera': sensorCamera,
        'sessionCompleted': sessionCompleted,
        'aiSummary': aiSummary,
        'weeklyTrend': weeklyTrend,
      };

  void _applyMap(Map<String, dynamic> m) {
    sensorCamera = m['sensorCamera'] as bool? ?? sensorCamera;
    sessionCompleted = m['sessionCompleted'] as bool? ?? sessionCompleted;
    aiSummary = m['aiSummary'] as bool? ?? aiSummary;
    weeklyTrend = m['weeklyTrend'] as bool? ?? weeklyTrend;
  }

  /// Loads from local storage. Call once at startup.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        _applyMap(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {/* keep defaults */}
    }
    notifyListeners();
  }

  /// Merges server-stored settings (e.g. from `profiles.notification_settings`)
  /// after login, then persists locally so they survive offline.
  Future<void> mergeFromServer(Map<String, dynamic>? settings) async {
    if (settings == null) return;
    _applyMap(settings);
    await _persistLocal();
    notifyListeners();
  }

  Future<void> setSensorCamera(bool v) => _set(() => sensorCamera = v);
  Future<void> setSessionCompleted(bool v) => _set(() => sessionCompleted = v);
  Future<void> setAiSummary(bool v) => _set(() => aiSummary = v);
  Future<void> setWeeklyTrend(bool v) => _set(() => weeklyTrend = v);

  Future<void> _set(void Function() change) async {
    change();
    notifyListeners();
    await _persistLocal();
    try {
      await onSync?.call(toMap());
    } catch (_) {/* sync is best-effort */}
  }

  Future<void> _persistLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(toMap()));
  }
}

/// Global instance used across the app.
final notificationPrefs = NotificationPrefs();
