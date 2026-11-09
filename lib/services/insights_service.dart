import '../models/detection_session.dart';
import '../models/emotion_reading.dart';
import 'supabase_service.dart';

typedef RawInsights = ({
  List<DetectionSession> sessions,
  List<EmotionReading> readings,
});

/// Supplies the raw session + reading data the insights are computed from.
/// Abstracted so the view model can be tested with in-memory data.
abstract class InsightsSource {
  Future<RawInsights> fetchRaw();
}

/// Pulls the signed-in user's sessions + readings from Supabase (one broad
/// window so every period filter can be served without refetching).
class SupabaseInsightsSource implements InsightsSource {
  final SupabaseService _svc;
  SupabaseInsightsSource([SupabaseService? svc]) : _svc = svc ?? SupabaseService();

  @override
  Future<RawInsights> fetchRaw() async {
    final uid = _svc.currentUserId;
    if (uid == null) {
      return (sessions: <DetectionSession>[], readings: <EmotionReading>[]);
    }
    final sessions = await _svc.fetchSessions(limit: 200);
    final readings = await _svc.fetchReadingsForUser(uid, limit: 5000);
    return (sessions: sessions, readings: readings);
  }
}
