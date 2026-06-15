/// A row from the Supabase `detection_sessions` table.
class DetectionSession {
  final String sessionId;
  final String userId;
  final DateTime startTime;
  final DateTime? endTime;
  final String status; // active | completed | cancelled
  final String? notes;

  const DetectionSession({
    required this.sessionId,
    required this.userId,
    required this.startTime,
    this.endTime,
    required this.status,
    this.notes,
  });

  bool get isActive => status == 'active';

  /// Length of the session — live elapsed time if still active.
  Duration get duration =>
      (endTime ?? DateTime.now()).difference(startTime);

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
    );
  }
}
