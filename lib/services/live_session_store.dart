import '../models/session_aggregates.dart';
import 'supabase_service.dart';

/// Persistence for a live session: per-reading rows + the final completion
/// update. Abstracted so the controller can be unit-tested with a fake store.
abstract class LiveSessionStore {
  Future<void> saveReading({
    required String sessionId,
    required String emotion,
    required double confidence,
    required int hr,
    required int spo2,
    required String sensorQuality,
  });

  /// Stamps the session completed + saves the aggregates. Returns false on
  /// failure so the caller can avoid claiming success.
  Future<bool> complete(String sessionId, SessionAggregates aggregates);
}

class SupabaseLiveSessionStore implements LiveSessionStore {
  final SupabaseService _svc;
  SupabaseLiveSessionStore([SupabaseService? svc]) : _svc = svc ?? SupabaseService();

  @override
  Future<void> saveReading({
    required String sessionId,
    required String emotion,
    required double confidence,
    required int hr,
    required int spo2,
    required String sensorQuality,
  }) {
    return _svc.saveReading(
      emotion: emotion,
      confidence: confidence,
      hr: hr,
      spo2: spo2,
      sensorQuality: sensorQuality,
      sessionId: sessionId,
    );
  }

  @override
  Future<bool> complete(String sessionId, SessionAggregates aggregates) async {
    try {
      await _svc.completeSession(sessionId, aggregates);
      return true;
    } catch (_) {
      return false;
    }
  }
}
