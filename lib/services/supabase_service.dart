import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/ai_insight.dart';
import '../models/app_notification.dart';
import '../models/detection_session.dart';
import '../models/emotion_reading.dart';
import '../models/session_aggregates.dart';
import '../models/session_liveness.dart';
import 'notification_service.dart';
import 'trend_service.dart';

class SupabaseService implements NotificationRepo {
  static const _url = 'https://vcgbfnuopsiraxhgwtgb.supabase.co';
  static const _anonKey = 'sb_publishable_jVLJSCTp5pCBb6J8vCkROg_dvHLGV5B';

  /// Public client config (the publishable key is not secret). Exposed so the
  /// admin "Add user" flow can use a throwaway client that signs the new
  /// account up without disturbing the administrator's own session.
  static String get url => _url;
  static String get publishableKey => _anonKey;

  static Future<void> init() =>
      Supabase.initialize(url: _url, publishableKey: _anonKey);

  SupabaseClient get _db => Supabase.instance.client;

  /// The signed-in user's id, or null when signed out.
  String? get currentUserId => _db.auth.currentUser?.id;

  /// Lightweight reachability probe. Completes if the Supabase backend is
  /// reachable over the internet; throws (e.g. SocketException) if offline.
  Future<void> ping() async {
    await _db.from('profiles').select('id').limit(1);
  }

  Future<void> saveReading({
    required String emotion,
    required double confidence,
    required int hr,
    required int spo2,
    required String sensorQuality,
    String? sessionId,
  }) async {
    await _db.from('emotion_readings').insert({
      'emotion': emotion,
      'confidence': confidence,
      'hr': hr,
      'spo2': spo2,
      'sensor_quality': sensorQuality,
      if (sessionId != null) 'session_id': sessionId,
      'user_id': _db.auth.currentUser?.id,
    });
  }

  /// Readings for a single user. Works for the signed-in user (their own rows)
  /// and for an admin viewing any user (via the admin RLS policy).
  Future<List<EmotionReading>> fetchReadingsForUser(
    String userId, {
    int limit = 1000,
  }) async {
    final data = await _db
        .from('emotion_readings')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(limit);
    return (data as List)
        .map((e) => EmotionReading.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ---- Detection sessions -------------------------------------------------

  /// Creates a new active session for the signed-in user and returns it.
  Future<DetectionSession> startSession() async {
    final user = _db.auth.currentUser;
    if (user == null) {
      throw Exception('Not signed in');
    }
    final data = await _db
        .from('detection_sessions')
        .insert({'user_id': user.id, 'status': 'active'})
        .select()
        .single();
    return DetectionSession.fromJson(data);
  }

  /// Marks a session finished (or cancelled) and stamps the end time.
  Future<void> endSession(
    String sessionId, {
    String status = 'completed',
    String? notes,
  }) async {
    await _db.from('detection_sessions').update({
      'end_time': DateTime.now().toUtc().toIso8601String(),
      'status': status,
      if (notes != null) 'notes': notes,
    }).eq('session_id', sessionId);
  }

  /// Self-heal: stamps abandoned `active` sessions as ended so they stop showing
  /// as "Live" forever across the app. For each, records `status = completed`
  /// and an `end_time` of its last reading (the real end of monitoring). The AI
  /// state is set terminal (`skipped`) because no summary will be generated for
  /// an abandoned session — that keeps it reading as plain "Completed" instead
  /// of being stuck in the "AI pending → Review" bucket.
  ///
  /// Best-effort and idempotent: each row is updated on its own and failures
  /// (RLS on another user's row, offline) are swallowed, because the display
  /// layer already treats these as ended regardless.
  Future<void> closeAbandonedSessions(
    List<DetectionSession> sessions,
    Map<String, DateTime?> lastReadingBySession, {
    DateTime? now,
  }) async {
    for (final c
        in abandonedActiveSessions(sessions, lastReadingBySession, now: now)) {
      try {
        await _db.from('detection_sessions').update({
          'status': 'completed',
          'end_time': c.endTime.toUtc().toIso8601String(),
          'ai_summary_status': 'skipped',
        }).eq('session_id', c.sessionId);
      } catch (_) {/* best-effort; display net still covers it */}
    }
  }

  /// Marks a session completed and saves its computed summary aggregates
  /// (from the live session). Throws on failure so the caller can react.
  Future<void> completeSession(
    String sessionId,
    SessionAggregates aggregates,
  ) async {
    final base = {
      'end_time': DateTime.now().toUtc().toIso8601String(),
      'status': 'completed',
    };
    try {
      await _db.from('detection_sessions').update({
        ...base,
        ...aggregates.toUpdateJson(),
      }).eq('session_id', sessionId);
    } catch (_) {
      // The summary columns may not exist yet (supabase_setup_session_summary.sql
      // not run). Fall back to marking the session completed so data isn't lost.
      await _db
          .from('detection_sessions')
          .update(base)
          .eq('session_id', sessionId);
    }
  }

  Future<List<DetectionSession>> fetchSessions({int limit = 100}) async {
    final user = _db.auth.currentUser;
    if (user == null) return [];
    final data = await _db
        .from('detection_sessions')
        .select()
        .eq('user_id', user.id)
        .order('start_time', ascending: false)
        .limit(limit);
    return (data as List)
        .map((e) => DetectionSession.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// The signed-in user's most recent completed-session baseline BPMs (newest
  /// first), used to derive a *personal* resting reference. Best-effort: returns
  /// an empty list if the column is missing / offline, so callers fall back to a
  /// fixed threshold.
  Future<List<int>> fetchRecentBaselines({int limit = 10}) async {
    final user = _db.auth.currentUser;
    if (user == null) return [];
    try {
      final data = await _db
          .from('detection_sessions')
          .select('baseline_bpm')
          .eq('user_id', user.id)
          .eq('status', 'completed')
          .not('baseline_bpm', 'is', null)
          .order('start_time', ascending: false)
          .limit(limit);
      return (data as List)
          .map((e) => (e['baseline_bpm'] as num?)?.toInt())
          .whereType<int>()
          .where((b) => b > 0)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<EmotionReading>> fetchReadingsForSession(String sessionId) async {
    final data = await _db
        .from('emotion_readings')
        .select()
        .eq('session_id', sessionId)
        .order('created_at', ascending: true);
    return (data as List)
        .map((e) => EmotionReading.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Sets the "flagged for review" state (+ optional note) on a session.
  /// Best-effort: silently no-ops if the columns aren't present yet.
  Future<bool> setSessionReview(
    String sessionId, {
    required bool flagged,
    String? note,
  }) async {
    try {
      await _db.from('detection_sessions').update({
        'flagged_for_review': flagged,
        if (note != null) 'review_note': note,
      }).eq('session_id', sessionId);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// The display name for a profile id (own row, or any when admin). Null if
  /// not readable.
  Future<String?> fetchProfileName(String userId) async {
    try {
      final data = await _db
          .from('profiles')
          .select('name, display_name, email')
          .eq('id', userId)
          .maybeSingle();
      if (data == null) return null;
      final display = data['display_name'] as String?;
      final name = data['name'] as String?;
      if (display?.trim().isNotEmpty == true) return display!.trim();
      if (name?.trim().isNotEmpty == true) return name!.trim();
      return data['email'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Deletes a session and its readings (own row via RLS; admins via the admin
  /// policy). Returns true on success.
  Future<bool> deleteSessionAndReadings(String sessionId) async {
    try {
      await _db.from('emotion_readings').delete().eq('session_id', sessionId);
      await _db.from('detection_sessions').delete().eq('session_id', sessionId);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Loads a single session by id (used by notification deep links).
  Future<DetectionSession> fetchSession(String sessionId) async {
    final data = await _db
        .from('detection_sessions')
        .select()
        .eq('session_id', sessionId)
        .single();
    return DetectionSession.fromJson(data);
  }

  // ---- AI session summary -------------------------------------------------

  /// Sets the AI summary status (pending | processing | completed | failed).
  Future<void> setSessionAiStatus(
    String sessionId,
    String status, {
    String? error,
  }) async {
    await _db.from('detection_sessions').update({
      'ai_summary_status': status,
      'ai_summary_error': error,
    }).eq('session_id', sessionId);
  }

  /// Stores a generated insight against the session and marks it completed.
  Future<void> saveSessionAiSummary(String sessionId, AiInsight insight) async {
    await _db.from('detection_sessions').update({
      'ai_summary': insight.toJson(),
      'ai_summary_status': 'completed',
      'ai_summary_error': null,
      'ai_generated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('session_id', sessionId);
  }

  /// Builds per-session aggregates for the weekly-trend engine using two
  /// queries (sessions + the user's readings), grouped client-side by session.
  Future<List<SessionStat>> fetchSessionStats({int sessionLimit = 200}) async {
    final user = _db.auth.currentUser;
    if (user == null) return [];

    final sessions = await fetchSessions(limit: sessionLimit);
    final completed = sessions.where((s) => s.status == 'completed').toList();
    if (completed.isEmpty) return [];

    final readings = await fetchReadingsForUser(user.id, limit: 5000);
    final bySession = <String, List<EmotionReading>>{};
    for (final r in readings) {
      final sid = r.sessionId;
      if (sid != null) (bySession[sid] ??= []).add(r);
    }

    return completed
        .map((s) => SessionStat.fromReadings(
              s.startTime.toLocal(),
              bySession[s.sessionId] ?? const [],
            ))
        .toList();
  }

  // ---- Notification settings (synced with profiles) -----------------------

  Future<Map<String, dynamic>?> loadNotificationSettings() async {
    final user = _db.auth.currentUser;
    if (user == null) return null;
    final data = await _db
        .from('profiles')
        .select('notification_settings')
        .eq('id', user.id)
        .maybeSingle();
    return (data?['notification_settings'] as Map?)?.cast<String, dynamic>();
  }

  Future<void> saveNotificationSettings(Map<String, dynamic> settings) async {
    final user = _db.auth.currentUser;
    if (user == null) return;
    await _db.from('profiles').upsert({
      'id': user.id,
      'email': user.email,
      'notification_settings': settings,
    });
  }

  // ---- NotificationRepo ---------------------------------------------------

  @override
  Future<List<AppNotification>> loadRecent({int limit = 100}) async {
    final user = _db.auth.currentUser;
    if (user == null) return [];
    final data = await _db
        .from('notifications')
        .select()
        .eq('user_id', user.id)
        .order('created_at', ascending: false)
        .limit(limit);
    return (data as List)
        .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<AppNotification?> insert(AppNotification draft) async {
    final user = _db.auth.currentUser;
    if (user == null) return null;
    final payload = draft.toInsertJson()..putIfAbsent('user_id', () => user.id);
    final data =
        await _db.from('notifications').insert(payload).select().single();
    return AppNotification.fromJson(data);
  }

  @override
  Future<void> markRead(String notificationId) async {
    await _db
        .from('notifications')
        .update({'is_read': true}).eq('notification_id', notificationId);
  }

  @override
  Future<void> markAllRead() async {
    final user = _db.auth.currentUser;
    if (user == null) return;
    await _db
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', user.id)
        .eq('is_read', false);
  }

  Future<List<EmotionReading>> fetchHistory({int limit = 200}) async {
    final data = await _db
        .from('emotion_readings')
        .select()
        .order('created_at', ascending: false)
        .limit(limit);
    return (data as List)
        .map((e) => EmotionReading.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  RealtimeChannel subscribeInserts(void Function(EmotionReading) onNew) {
    return _db
        .channel('meds_live')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'emotion_readings',
          callback: (payload) =>
              onNew(EmotionReading.fromJson(payload.newRecord)),
        )
        .subscribe();
  }
}
