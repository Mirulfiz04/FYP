import 'package:flutter/foundation.dart';

import '../models/app_notification.dart';
import 'deep_links.dart';
import 'notification_prefs.dart';

/// Fires an OS-level local notification. Wired to [LocalNotifications] in main;
/// left null in tests so no plugin is touched.
typedef PushFn = Future<void> Function(AppNotification notification);

/// Backend persistence for notifications. Implemented by [SupabaseService];
/// swapped for an in-memory fake in tests.
abstract class NotificationRepo {
  Future<List<AppNotification>> loadRecent({int limit});
  Future<AppNotification?> insert(AppNotification draft);
  Future<void> markRead(String notificationId);
  Future<void> markAllRead();
}

/// Central in-app notification store and dispatcher.
///
/// Responsibilities:
///  • holds the in-app list (source of truth for the Notification Centre);
///  • gates optional notifications by [NotificationPrefs];
///  • de-duplicates via a per-key cooldown;
///  • best-effort persists to a [NotificationRepo] and pushes via [PushFn].
///
/// A [ChangeNotifier] singleton like [themeController] — the UI listens with
/// `AnimatedBuilder` / `ListenableBuilder`.
class NotificationService extends ChangeNotifier {
  final NotificationPrefs prefs;
  NotificationRepo? repo;
  PushFn? push;
  final DateTime Function() _clock;

  NotificationService({
    NotificationPrefs? prefs,
    this.repo,
    this.push,
    DateTime Function()? clock,
  })  : prefs = prefs ?? NotificationPrefs(),
        _clock = clock ?? DateTime.now;

  final List<AppNotification> _items = [];
  final Map<String, DateTime> _lastByKey = {};

  List<AppNotification> get items => List.unmodifiable(_items);
  int get unreadCount => _items.where((n) => !n.isRead).length;
  bool get hasUnread => unreadCount > 0;

  /// Loads recent notifications from the backend (call after login).
  Future<void> loadFromRepo() async {
    final r = repo;
    if (r == null) return;
    try {
      final loaded = await r.loadRecent(limit: 100);
      _items
        ..clear()
        ..addAll(loaded);
      notifyListeners();
    } catch (_) {/* offline — keep whatever we have */}
  }

  /// Adds a notification.
  ///
  /// Returns the stored notification, or null when it was suppressed because
  /// (a) [optional] is true and the user disabled that category, or (b) an
  /// identical one fired within [cooldown].
  Future<AppNotification?> add(
    AppNotification draft, {
    Duration? cooldown,
    String dedupeKey = '',
    bool optional = true,
    bool alsoPush = true,
  }) async {
    if (optional && !prefs.isEnabled(draft.type)) return null;

    final key = '${draft.type.wire}:${draft.sessionId ?? ''}:$dedupeKey';
    final now = _clock();
    if (cooldown != null) {
      final last = _lastByKey[key];
      if (last != null && now.difference(last) < cooldown) return null;
    }
    _lastByKey[key] = now;

    var item = draft;
    final r = repo;
    if (r != null) {
      try {
        final saved = await r.insert(draft);
        if (saved != null) item = saved;
      } catch (_) {/* keep the client-side draft if the insert fails */}
    }

    _items.insert(0, item);
    notifyListeners();

    if (alsoPush && push != null) {
      try {
        await push!(item);
      } catch (_) {/* OS push is best-effort */}
    }
    return item;
  }

  Future<void> markRead(String notificationId) async {
    final i = _items.indexWhere((n) => n.notificationId == notificationId);
    if (i < 0 || _items[i].isRead) return;
    _items[i] = _items[i].copyWith(isRead: true);
    notifyListeners();
    try {
      await repo?.markRead(notificationId);
    } catch (_) {}
  }

  Future<void> markAllRead() async {
    var changed = false;
    for (var i = 0; i < _items.length; i++) {
      if (!_items[i].isRead) {
        _items[i] = _items[i].copyWith(isRead: true);
        changed = true;
      }
    }
    if (!changed) return;
    notifyListeners();
    try {
      await repo?.markAllRead();
    } catch (_) {}
  }

  /// Clears the in-memory list (e.g. on sign-out). Does not touch the backend.
  void reset() {
    _items.clear();
    _lastByKey.clear();
    notifyListeners();
  }

  // ---- Typed convenience builders ----------------------------------------

  Future<AppNotification?> sessionCompleted({
    required String sessionId,
    String? userId,
  }) {
    return add(
      AppNotification.draft(
        type: NotificationType.sessionCompleted,
        title: 'Session complete',
        message:
            'Your monitoring session has been completed. The session summary is ready.',
        sessionId: sessionId,
        userId: userId,
        deepLink: DeepLinks.session(sessionId),
      ),
      cooldown: const Duration(minutes: 1),
    );
  }

  Future<AppNotification?> aiSummaryReady({
    required String sessionId,
    String? userId,
  }) {
    return add(
      AppNotification.draft(
        type: NotificationType.aiSummaryReady,
        title: 'AI insight ready',
        message: 'Your AI session insight is ready to view.',
        sessionId: sessionId,
        userId: userId,
        deepLink: DeepLinks.sessionAi(sessionId),
      ),
      cooldown: const Duration(minutes: 1),
    );
  }

  Future<AppNotification?> aiSummaryFailed({
    required String sessionId,
    String? userId,
  }) {
    return add(
      AppNotification.draft(
        type: NotificationType.aiSummaryFailed,
        title: 'AI insight failed',
        message: 'AI insight could not be generated. Please try again.',
        sessionId: sessionId,
        userId: userId,
        deepLink: DeepLinks.sessionAi(sessionId),
        metadata: const {'retry': true},
      ),
      cooldown: const Duration(seconds: 30),
    );
  }

  Future<AppNotification?> weeklyTrend({
    required String message,
    String? evidence,
    String? userId,
  }) {
    return add(
      AppNotification.draft(
        type: NotificationType.weeklyTrend,
        title: 'Weekly emotional trend',
        message: message,
        userId: userId,
        deepLink: DeepLinks.trends,
        metadata: {if (evidence != null) 'evidence': evidence},
      ),
      cooldown: const Duration(days: 1),
    );
  }
}

/// Global instance — push + repo are wired in main once Supabase / the local
/// notifications plugin are available.
final notifications = NotificationService(prefs: notificationPrefs);
