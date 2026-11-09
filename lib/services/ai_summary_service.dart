import 'package:flutter/foundation.dart';

import '../models/ai_insight.dart';
import 'ai_service.dart';
import 'notification_service.dart';
import 'supabase_service.dart';

/// Orchestrates the AI session-summary lifecycle, separated from sensor and
/// session events:
///   pending → processing → (completed + aiSummaryReady) | (failed + aiSummaryFailed)
///
/// The summary is stored against the session in the database. Notifications are
/// fired through the shared [notifications] service (which respects prefs and
/// dedupes), so the user is alerted only when generation actually completes or
/// fails — never while it is still processing.
class AiSummaryService {
  final AiService _ai;
  final SupabaseService _svc;

  AiSummaryService({AiService? ai, SupabaseService? svc})
      : _ai = ai ?? AiService(),
        _svc = svc ?? SupabaseService();

  /// Generates and stores the insight for [sessionId]. Returns the insight on
  /// success, or null on failure. Safe to call again to retry a failed run.
  Future<AiInsight?> generateForSession(
    String sessionId, {
    String? userId,
  }) async {
    try {
      await _svc.setSessionAiStatus(sessionId, 'processing');
    } catch (e) {
      debugPrint('AiSummaryService: could not mark processing: $e');
    }

    try {
      final readings = await _svc.fetchReadingsForSession(sessionId);
      if (readings.isEmpty) {
        await _fail(sessionId, 'No readings to analyze.', userId);
        return null;
      }

      final insight = await _ai.generateInsight(readings);
      try {
        await _svc.saveSessionAiSummary(sessionId, insight);
      } catch (e) {
        debugPrint('AiSummaryService: could not save summary: $e');
      }
      await notifications.aiSummaryReady(sessionId: sessionId, userId: userId);
      return insight;
    } catch (e) {
      debugPrint('AiSummaryService: generation failed: $e');
      await _fail(sessionId, e.toString(), userId);
      return null;
    }
  }

  Future<void> _fail(String sessionId, String error, String? userId) async {
    try {
      await _svc.setSessionAiStatus(sessionId, 'failed', error: error);
    } catch (_) {}
    await notifications.aiSummaryFailed(sessionId: sessionId, userId: userId);
  }
}
