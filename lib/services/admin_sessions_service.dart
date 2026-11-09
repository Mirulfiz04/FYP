import 'dart:async';

import '../models/admin_sessions_model.dart';
import 'admin_service.dart';
import 'supabase_service.dart';

/// Test seam so the Monitor Sessions screen can run against fake data without a
/// live Supabase connection.
abstract interface class AdminSessionsSource {
  Future<MonitorSessionsData> fetchSessions();
}

/// Loads the Monitor Sessions view by reusing the existing [AdminService]
/// queries and delegating to the pure [MonitorSessionsData.build].
class AdminSessionsService implements AdminSessionsSource {
  final AdminService _admin;
  final SupabaseService _svc;

  AdminSessionsService([AdminService? admin, SupabaseService? svc])
      : _admin = admin ?? AdminService(),
        _svc = svc ?? SupabaseService();

  @override
  Future<MonitorSessionsData> fetchSessions() async {
    final users = await _admin.fetchAllUsers();
    final sessions = await _admin.fetchAllSessions();
    final readings = await _admin.fetchRecentReadings();

    // Self-heal any sessions stuck "active" because their owner closed the app
    // without ending them. Best-effort across users (relies on the admin RLS
    // update policy); the display net keeps the list correct regardless.
    final lastReadingBySession = <String, DateTime?>{};
    for (final r in readings) {
      final sid = r.sessionId;
      if (sid == null) continue;
      final cur = lastReadingBySession[sid];
      if (cur == null || r.createdAt.isAfter(cur)) {
        lastReadingBySession[sid] = r.createdAt;
      }
    }
    unawaited(_svc.closeAbandonedSessions(sessions, lastReadingBySession));

    return MonitorSessionsData.build(
      users: users,
      sessions: sessions,
      readings: readings,
    );
  }
}
