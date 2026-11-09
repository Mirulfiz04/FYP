import '../models/detection_session.dart';
import '../models/emotion_reading.dart';
import '../models/session_analytics.dart';
import 'auth_service.dart';
import 'supabase_service.dart';

/// Everything the Session Details page needs for one session.
class SessionDetailsData {
  final DetectionSession session;
  final List<EmotionReading> readings;
  final SessionAnalytics analytics;
  final String? userName;
  final bool viewerIsAdmin;
  final bool isOwner;

  const SessionDetailsData({
    required this.session,
    required this.readings,
    required this.analytics,
    required this.userName,
    required this.viewerIsAdmin,
    required this.isOwner,
  });

  /// Returns a copy with a refreshed [session] (used by the AI-summary poll,
  /// which only needs the session row, not the readings/analytics again).
  SessionDetailsData copyWith({DetectionSession? session}) => SessionDetailsData(
        session: session ?? this.session,
        readings: readings,
        analytics: analytics,
        userName: userName,
        viewerIsAdmin: viewerIsAdmin,
        isOwner: isOwner,
      );
}

/// Loads + mutates session-details data. Keeps Supabase out of the controller
/// and UI, and is swappable with a fake in tests.
abstract class SessionDetailsService {
  Future<SessionDetailsData> load(String sessionId);

  /// Re-fetches just the session row — cheap enough to poll while the AI summary
  /// is still being generated.
  Future<DetectionSession> reloadSession(String sessionId);

  Future<bool> setReview(String sessionId, bool flagged);
  Future<bool> delete(String sessionId);
}

class SupabaseSessionDetailsService implements SessionDetailsService {
  final SupabaseService _svc;
  final AuthService _auth;
  SupabaseSessionDetailsService([SupabaseService? svc, AuthService? auth])
      : _svc = svc ?? SupabaseService(),
        _auth = auth ?? AuthService();

  @override
  Future<SessionDetailsData> load(String sessionId) async {
    final session = await _svc.fetchSession(sessionId);
    final readings = await _svc.fetchReadingsForSession(sessionId);
    final analytics = SessionAnalytics.from(readings);

    final profile = await _auth.loadProfile();
    final isOwner = session.userId == _svc.currentUserId;
    final userName = isOwner
        ? profile.displayLabel
        : (profile.isAdmin ? await _svc.fetchProfileName(session.userId) : null);

    return SessionDetailsData(
      session: session,
      readings: readings,
      analytics: analytics,
      userName: userName,
      viewerIsAdmin: profile.isAdmin,
      isOwner: isOwner,
    );
  }

  @override
  Future<DetectionSession> reloadSession(String sessionId) =>
      _svc.fetchSession(sessionId);

  @override
  Future<bool> setReview(String sessionId, bool flagged) =>
      _svc.setSessionReview(sessionId, flagged: flagged);

  @override
  Future<bool> delete(String sessionId) =>
      _svc.deleteSessionAndReadings(sessionId);
}
