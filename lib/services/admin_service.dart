import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/detection_session.dart';
import '../models/emotion_reading.dart';
import '../models/user_profile.dart';

/// Per-user emotion contribution, used by the "by user" breakdown so an admin
/// can see who contributed each emotion.
class UserEmotionSummary {
  final String? userId; // null = legacy readings with no owner
  final String label; // name / email / "Unattributed"
  final String? avatarUrl;
  final int readingCount;
  final String dominantEmotion;
  final Map<String, int> emotionCounts;
  final int avgHr;

  const UserEmotionSummary({
    required this.userId,
    required this.label,
    required this.avatarUrl,
    required this.readingCount,
    required this.dominantEmotion,
    required this.emotionCounts,
    required this.avgHr,
  });
}

/// Aggregated numbers for the analytics dashboard.
class AdminStats {
  final int totalUsers;
  final int totalAdmins;
  final int totalSessions;
  final int activeSessions;
  final int completedSessions;
  final int totalReadings;
  final Map<String, int> emotionCounts; // from a recent sample
  final int emotionSampleSize;
  final Duration avgSessionDuration;
  final List<UserEmotionSummary> perUser;

  const AdminStats({
    required this.totalUsers,
    required this.totalAdmins,
    required this.totalSessions,
    required this.activeSessions,
    required this.completedSessions,
    required this.totalReadings,
    required this.emotionCounts,
    required this.emotionSampleSize,
    required this.avgSessionDuration,
    required this.perUser,
  });
}

/// Admin-only data access. Every method here relies on the admin RLS policies
/// from `supabase_setup_admin.sql`; a non-admin will simply get their own rows.
class AdminService {
  final SupabaseClient _db = Supabase.instance.client;

  // ---- Users --------------------------------------------------------------

  Future<List<UserProfile>> fetchAllUsers() async {
    final data = await _db
        .from('profiles')
        .select()
        .order('created_at', ascending: false);
    return (data as List)
        .map((e) => UserProfile.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> setUserRole(String userId, String role) async {
    await _db.from('profiles').update({'role': role}).eq('id', userId);
  }

  Future<void> setUserStatus(String userId, String status) async {
    await _db.from('profiles').update({'status': status}).eq('id', userId);
  }

  // ---- Sessions -----------------------------------------------------------

  Future<List<DetectionSession>> fetchAllSessions({int limit = 500}) async {
    final data = await _db
        .from('detection_sessions')
        .select()
        .order('start_time', ascending: false)
        .limit(limit);
    return (data as List)
        .map((e) => DetectionSession.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ---- Readings -----------------------------------------------------------

  Future<List<EmotionReading>> fetchRecentReadings({int limit = 1000}) async {
    final data = await _db
        .from('emotion_readings')
        .select()
        .order('created_at', ascending: false)
        .limit(limit);
    return (data as List)
        .map((e) => EmotionReading.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Exact row count for a table (used by analytics + system status).
  Future<int> countRows(String table) async {
    return _db.from(table).count(CountOption.exact);
  }

  // ---- Aggregated analytics ----------------------------------------------

  Future<AdminStats> fetchStats() async {
    final users = await fetchAllUsers();
    final sessions = await fetchAllSessions();
    final readings = await fetchRecentReadings();

    int totalReadings;
    try {
      totalReadings = await countRows('emotion_readings');
    } catch (_) {
      totalReadings = readings.length; // fall back to the sample size
    }

    final emotionCounts = <String, int>{};
    for (final r in readings) {
      emotionCounts[r.emotion] = (emotionCounts[r.emotion] ?? 0) + 1;
    }

    final completed = sessions.where((s) => s.endTime != null).toList();
    Duration avg = Duration.zero;
    if (completed.isNotEmpty) {
      final totalSecs = completed.fold<int>(
          0, (sum, s) => sum + s.duration.inSeconds);
      avg = Duration(seconds: (totalSecs / completed.length).round());
    }

    return AdminStats(
      totalUsers: users.length,
      totalAdmins: users.where((u) => u.isAdmin).length,
      totalSessions: sessions.length,
      activeSessions: sessions.where((s) => s.status == 'active').length,
      completedSessions: sessions.where((s) => s.status == 'completed').length,
      totalReadings: totalReadings,
      emotionCounts: emotionCounts,
      emotionSampleSize: readings.length,
      avgSessionDuration: avg,
      perUser: _buildPerUser(users, readings),
    );
  }

  /// Groups the readings sample by user so the dashboard can show who
  /// contributed which emotions.
  List<UserEmotionSummary> _buildPerUser(
    List<UserProfile> users,
    List<EmotionReading> readings,
  ) {
    final byId = {for (final u in users) u.id: u};
    final grouped = <String?, List<EmotionReading>>{};
    for (final r in readings) {
      grouped.putIfAbsent(r.userId, () => []).add(r);
    }

    final result = <UserEmotionSummary>[];
    grouped.forEach((userId, rows) {
      final counts = <String, int>{};
      for (final r in rows) {
        counts[r.emotion] = (counts[r.emotion] ?? 0) + 1;
      }
      final dominant = counts.entries
          .reduce((a, b) => a.value >= b.value ? a : b)
          .key;
      final hrValues = rows.where((r) => r.hr > 0).map((r) => r.hr).toList();
      final avgHr = hrValues.isEmpty
          ? 0
          : (hrValues.reduce((a, b) => a + b) / hrValues.length).round();
      final profile = userId != null ? byId[userId] : null;
      final label = profile?.name?.isNotEmpty == true
          ? profile!.name!
          : (profile?.email ?? (userId == null ? 'Unattributed (legacy)' : userId));

      result.add(UserEmotionSummary(
        userId: userId,
        label: label,
        avatarUrl: profile?.avatarUrl,
        readingCount: rows.length,
        dominantEmotion: dominant,
        emotionCounts: counts,
        avgHr: avgHr,
      ));
    });

    result.sort((a, b) => b.readingCount.compareTo(a.readingCount));
    return result;
  }
}
