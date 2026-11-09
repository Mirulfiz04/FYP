import 'package:flutter_test/flutter_test.dart';
import 'package:meds_flutter_no_python/models/app_notification.dart';
import 'package:meds_flutter_no_python/services/deep_links.dart';
import 'package:meds_flutter_no_python/services/notification_prefs.dart';
import 'package:meds_flutter_no_python/services/notification_service.dart';
import 'package:meds_flutter_no_python/services/session_alert_controller.dart';
import 'package:meds_flutter_no_python/services/trend_service.dart';

/// In-memory [NotificationRepo] so the service can be exercised without
/// Supabase. Assigns deterministic ids on insert.
class _InMemoryRepo implements NotificationRepo {
  final List<AppNotification> store = [];
  int _seq = 0;

  @override
  Future<List<AppNotification>> loadRecent({int limit = 100}) async =>
      List.of(store.reversed);

  @override
  Future<AppNotification?> insert(AppNotification draft) async {
    final saved = draft.copyWith(notificationId: 'db_${_seq++}');
    store.add(saved);
    return saved;
  }

  @override
  Future<void> markRead(String notificationId) async {}

  @override
  Future<void> markAllRead() async {}
}

SessionStat _stat(DateTime date,
        {double bpm = 80,
        double stress = 0.2,
        String emotion = 'Neutral',
        bool valid = true}) =>
    SessionStat(
      date: date,
      avgBpm: bpm,
      stressScore: stress,
      dominantEmotion: emotion,
      valid: valid,
    );

void main() {
  group('1. Sensor disconnection warning', () {
    test('appears with a Retry action when the sensor disconnects', () {
      final c = SessionAlertController();
      c.onSensorQuality('DISCONNECTED');

      expect(c.currentAlert, isNotNull);
      expect(c.currentAlert!.type, NotificationType.sensorDisconnected);
      expect(c.currentAlert!.hasRetry, isTrue);
      expect(c.sensorState, IndicatorState.error);
    });
  });

  group('2. Repeated low-signal events do not duplicate', () {
    test('emits at most once per cooldown window', () {
      var now = DateTime(2026, 1, 1, 12, 0, 0);
      final c = SessionAlertController(
        cooldown: const Duration(seconds: 7),
        clock: () => now,
      );

      var emits = 0;
      for (var i = 0; i < 10; i++) {
        c.onSensorQuality('BAD SIGNAL');
        if (c.shouldEmit(NotificationType.lowSensorQuality)) emits++;
      }
      expect(emits, 1, reason: '10 rapid low-signal events → one emission');

      // Once the cooldown elapses, a new emission is allowed.
      now = now.add(const Duration(seconds: 8));
      expect(c.shouldEmit(NotificationType.lowSensorQuality), isTrue);
    });
  });

  group('3. Session-completed opens the correct session', () {
    test('payload deep link carries the right sessionId', () async {
      final svc = NotificationService(prefs: NotificationPrefs(), repo: _InMemoryRepo());
      final n = await svc.sessionCompleted(sessionId: 'sess-123', userId: 'u1');

      expect(n, isNotNull);
      final target = DeepLinks.parse(n!.deepLink);
      expect(target?.kind, DeepLinkKind.sessionDetail);
      expect(target?.sessionId, 'sess-123');
    });
  });

  group('4. AI summary notification only after success', () {
    test('no ready notification until completion, then exactly one', () async {
      final svc = NotificationService(prefs: NotificationPrefs(), repo: _InMemoryRepo());

      // Before completion there is no aiSummaryReady notification.
      expect(
        svc.items.where((n) => n.type == NotificationType.aiSummaryReady),
        isEmpty,
      );

      await svc.aiSummaryReady(sessionId: 's1', userId: 'u1');
      expect(
        svc.items.where((n) => n.type == NotificationType.aiSummaryReady).length,
        1,
      );
    });
  });

  group('5. Failed AI summary provides a retry', () {
    test('failed notification flags retry and links to the AI section', () async {
      final svc = NotificationService(prefs: NotificationPrefs(), repo: _InMemoryRepo());
      final n = await svc.aiSummaryFailed(sessionId: 's1');

      expect(n, isNotNull);
      expect(n!.type, NotificationType.aiSummaryFailed);
      expect(n.metadata['retry'], isTrue);
      expect(DeepLinks.parse(n.deepLink)?.showAi, isTrue);
    });
  });

  group('6. Weekly trend needs enough data', () {
    test('insufficient sessions → no trend, shows the in-app hint', () {
      final stats = List.generate(
        3,
        (i) => _stat(DateTime(2026, 1, 1).add(Duration(days: i))),
      );
      final eval = TrendService.evaluate(stats);

      expect(eval.enough, isFalse);
      expect(eval.direction, TrendDirection.insufficient);
      expect(eval.message, contains('More sessions are needed'));
    });

    test('enough valid data across two weeks → a trend is produced', () {
      final now = DateTime(2026, 6, 17, 12);
      final stats = <SessionStat>[
        // last week — higher stress
        _stat(now.subtract(const Duration(days: 9)), stress: 0.6, bpm: 88),
        _stat(now.subtract(const Duration(days: 8)), stress: 0.6, bpm: 86),
        // this week — lower stress
        _stat(now.subtract(const Duration(days: 3)), stress: 0.2, bpm: 78),
        _stat(now.subtract(const Duration(days: 2)), stress: 0.2, bpm: 76),
        _stat(now.subtract(const Duration(days: 1)), stress: 0.2, bpm: 77),
      ];
      final eval = TrendService.evaluate(stats, now: now);

      expect(eval.enough, isTrue);
      expect(eval.direction, TrendDirection.improved);
      expect(eval.evidence, isNotNull);
    });
  });

  group('7. Weekly trend at most once per week', () {
    test('isNewWeek is false within the same week, true across weeks', () {
      // Build dates relative to a real Monday so the test is calendar-robust.
      final base = DateTime(2026, 6, 15);
      final monday = base.subtract(Duration(days: base.weekday - 1));
      final wednesday = monday.add(const Duration(days: 2));
      final thursday = monday.add(const Duration(days: 3));
      final lastSunday = monday.subtract(const Duration(days: 1));

      expect(TrendService.isNewWeek(thursday, null), isTrue);
      expect(TrendService.isNewWeek(thursday, wednesday), isFalse);
      expect(TrendService.isNewWeek(thursday, lastSunday), isTrue);
    });
  });

  group('8. Disabled preferences prevent optional notifications', () {
    test('off switches suppress both the in-app entry and OS push', () async {
      final pushed = <AppNotification>[];
      final svc = NotificationService(
        prefs: NotificationPrefs(weeklyTrend: false, sessionCompleted: false),
        repo: _InMemoryRepo(),
        push: (n) async => pushed.add(n),
      );

      expect(await svc.weeklyTrend(message: 'trend'), isNull);
      expect(await svc.sessionCompleted(sessionId: 's1'), isNull);
      expect(svc.items, isEmpty);
      expect(pushed, isEmpty);

      // An enabled category still gets through.
      final on = NotificationService(
        prefs: NotificationPrefs(), // sessionCompleted defaults ON
        repo: _InMemoryRepo(),
        push: (n) async => pushed.add(n),
      );
      expect(await on.sessionCompleted(sessionId: 's1'), isNotNull);
      expect(pushed.length, 1);
    });
  });

  group('9. Read / unread states', () {
    test('unread count tracks mark-one and mark-all', () async {
      final svc = NotificationService(prefs: NotificationPrefs(), repo: _InMemoryRepo());
      final a = await svc.sessionCompleted(sessionId: 's1');
      await svc.aiSummaryReady(sessionId: 's2');

      expect(svc.unreadCount, 2);

      await svc.markRead(a!.notificationId);
      expect(svc.unreadCount, 1);

      await svc.markAllRead();
      expect(svc.unreadCount, 0);
    });
  });
}
