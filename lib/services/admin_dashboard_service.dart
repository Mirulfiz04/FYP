import '../models/admin_dashboard_models.dart';
import 'admin_service.dart';

/// A narrow seam the dashboard depends on, so it can be faked in tests without
/// a live Supabase connection (mirrors the `InsightsSource` pattern).
abstract interface class AdminDashboardSource {
  Future<DashboardData> fetchDashboard({
    DashboardPeriod period,
    DateTime? customStart,
    DateTime? customEnd,
  });
}

/// Loads everything the Admin Dashboard needs by reusing the existing
/// [AdminService] queries, then delegates the number-crunching to the pure
/// [DashboardData.build]. No SQL or Supabase types leak into the UI.
class AdminDashboardService implements AdminDashboardSource {
  final AdminService _admin;

  AdminDashboardService([AdminService? admin]) : _admin = admin ?? AdminService();

  @override
  Future<DashboardData> fetchDashboard({
    DashboardPeriod period = DashboardPeriod.week,
    DateTime? customStart,
    DateTime? customEnd,
  }) async {
    final users = await _admin.fetchAllUsers();
    final sessions = await _admin.fetchAllSessions();
    final readings = await _admin.fetchRecentReadings();

    int totalReadings;
    try {
      totalReadings = await _admin.countRows('emotion_readings');
    } catch (_) {
      totalReadings = readings.length; // fall back to the sample size
    }

    return DashboardData.build(
      users: users,
      sessions: sessions,
      readings: readings,
      totalReadings: totalReadings,
      period: period,
      customStart: customStart,
      customEnd: customEnd,
    );
  }
}
