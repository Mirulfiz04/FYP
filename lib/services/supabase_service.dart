import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/detection_session.dart';
import '../models/emotion_reading.dart';

class SupabaseService {
  static const _url = 'https://vcgbfnuopsiraxhgwtgb.supabase.co';
  static const _anonKey = 'sb_publishable_jVLJSCTp5pCBb6J8vCkROg_dvHLGV5B';

  static Future<void> init() =>
      Supabase.initialize(url: _url, publishableKey: _anonKey);

  SupabaseClient get _db => Supabase.instance.client;

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
