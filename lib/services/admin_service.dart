import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/detection_session.dart';
import '../models/emotion_reading.dart';
import '../models/user_profile.dart';
import 'supabase_service.dart';

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

/// Narrow seam the Manage Users screen depends on, so it can be faked in tests
/// without a live Supabase connection.
abstract interface class AdminUsersSource {
  Future<List<UserProfile>> fetchAllUsers();
  Future<void> setUserRole(String userId, String role);
  Future<void> setUserStatus(String userId, String status);
  Future<void> updateUser(String userId,
      {String? name, String? role, String? status});
  Future<void> deleteUser(String userId);
}

/// Admin-only data access. Every method here relies on the admin RLS policies
/// from `supabase_setup_admin.sql`; a non-admin will simply get their own rows.
class AdminService implements AdminUsersSource {
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

  /// Creates a new account as an administrator. Runs the sign-up on a *separate*
  /// Supabase client so the administrator's own session is never replaced, then
  /// sets the role/status on the freshly-created profile (admin RLS). Requires
  /// "Confirm email" to be OFF for the account to be usable immediately.
  Future<void> createUser({
    required String name,
    required String email,
    required String password,
    String role = 'user',
    String status = 'active',
  }) async {
    final temp = SupabaseClient(
        SupabaseService.url, SupabaseService.publishableKey);
    try {
      final res = await temp.auth.signUp(
        email: email,
        password: password,
        data: {'name': name},
      );
      final newId = res.user?.id;
      if (newId == null) {
        throw Exception('Sign-up did not return a user.');
      }
      // The DB trigger creates the profile row; upsert applies the admin's
      // chosen role/status (and fills the name in case the trigger raced).
      await _db.from('profiles').upsert({
        'id': newId,
        'email': email,
        'name': name,
        'role': role,
        'status': status,
      });
    } finally {
      await temp.dispose();
    }
  }

  /// Updates editable profile fields for any user (admin RLS). Only the
  /// provided fields are written.
  @override
  Future<void> updateUser(String userId,
      {String? name, String? role, String? status}) async {
    final patch = <String, dynamic>{};
    if (name != null) patch['name'] = name;
    if (role != null) patch['role'] = role;
    if (status != null) patch['status'] = status;
    if (patch.isEmpty) return;
    await _db.from('profiles').update(patch).eq('id', userId);
  }

  /// Fully deletes a user account.
  ///
  /// Prefers the `admin_delete_user` security-definer RPC (from
  /// `supabase_setup_admin_user_mgmt.sql`), which removes the user's data AND
  /// their auth login so they can no longer sign in. If that function is not
  /// installed, it falls back to removing the profile row (+ best-effort data)
  /// via the admin RLS policies — note the auth login then survives until it is
  /// removed server-side.
  @override
  Future<void> deleteUser(String userId) async {
    try {
      await _db.rpc('admin_delete_user', params: {'target_id': userId});
      return;
    } catch (_) {
      // Function missing / insufficient privilege — fall back to RLS deletes.
    }
    for (final table in ['notifications', 'emotion_readings', 'detection_sessions']) {
      try {
        await _db.from(table).delete().eq('user_id', userId);
      } catch (_) {
        // No admin delete policy on these tables — ignore and continue.
      }
    }
    await _db.from('profiles').delete().eq('id', userId);
  }

  Future<List<DetectionSession>> fetchSessionsForUser(String userId) async {
    final data = await _db
        .from('detection_sessions')
        .select()
        .eq('user_id', userId)
        .order('start_time', ascending: false);
    return (data as List)
        .map((e) => DetectionSession.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<EmotionReading>> fetchReadingsForUser(String userId,
      {int limit = 2000}) async {
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
