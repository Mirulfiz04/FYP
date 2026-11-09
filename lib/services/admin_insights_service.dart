import '../models/admin_insights_model.dart';
import 'admin_service.dart';

/// Test seam so the Insights view-model can run against fake data without a
/// live Supabase connection.
abstract interface class AdminInsightsSource {
  Future<AdminInsightsData> fetchInsights({
    AdminInsightsPeriod period,
    DateTime? customStart,
    DateTime? customEnd,
  });
}

/// Loads platform-wide Insights by reusing the existing [AdminService] queries
/// and delegating the analytics to the pure [AdminInsightsData.build].
class AdminInsightsService implements AdminInsightsSource {
  final AdminService _admin;

  AdminInsightsService([AdminService? admin]) : _admin = admin ?? AdminService();

  @override
  Future<AdminInsightsData> fetchInsights({
    AdminInsightsPeriod period = AdminInsightsPeriod.week,
    DateTime? customStart,
    DateTime? customEnd,
  }) async {
    final users = await _admin.fetchAllUsers();
    final sessions = await _admin.fetchAllSessions();
    final readings = await _admin.fetchRecentReadings();

    return AdminInsightsData.build(
      users: users,
      sessions: sessions,
      readings: readings,
      period: period,
      customStart: customStart,
      customEnd: customEnd,
    );
  }
}
