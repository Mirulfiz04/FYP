import 'ai_insight.dart';

/// A row from the Supabase `detection_sessions` table.
class DetectionSession {
  final String sessionId;
  final String userId;
  final DateTime startTime;
  final DateTime? endTime;
  final String status; // active | completed | cancelled
  final String? notes;

  // AI summary tracking (added by supabase_setup_notifications.sql).
  final String aiSummaryStatus; // pending | processing | completed | failed
  final AiInsight? aiSummary;
  final String? aiSummaryError;
  final DateTime? aiGeneratedAt;

  // Review flag (added by supabase_setup_session_review.sql).
  final bool flaggedForReview;
  final String? reviewNote;

  const DetectionSession({
    required this.sessionId,
    required this.userId,
    required this.startTime,
    this.endTime,
    required this.status,
    this.notes,
    this.aiSummaryStatus = 'pending',
    this.aiSummary,
    this.aiSummaryError,
    this.aiGeneratedAt,
    this.flaggedForReview = false,
    this.reviewNote,
  });

  bool get isActive => status == 'active';

  /// Length of the session — live elapsed time if still active.
  Duration get duration => (endTime ?? DateTime.now()).difference(startTime);

  factory DetectionSession.fromJson(Map<String, dynamic> json) {
    return DetectionSession(
      sessionId: json['session_id'] as String,
      userId: json['user_id'] as String,
      startTime: DateTime.parse(json['start_time'] as String),
      endTime: json['end_time'] != null
          ? DateTime.parse(json['end_time'] as String)
          : null,
      status: json['status'] as String? ?? 'active',
      notes: json['notes'] as String?,
      aiSummaryStatus: json['ai_summary_status'] as String? ?? 'pending',
      aiSummary: json['ai_summary'] is Map<String, dynamic>
          ? AiInsight.fromJson(json['ai_summary'] as Map<String, dynamic>)
          : null,
      aiSummaryError: json['ai_summary_error'] as String?,
      aiGeneratedAt: json['ai_generated_at'] != null
          ? DateTime.tryParse(json['ai_generated_at'] as String)
          : null,
      flaggedForReview: json['flagged_for_review'] as bool? ?? false,
      reviewNote: json['review_note'] as String?,
    );
  }
}
