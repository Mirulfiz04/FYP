/// The kind of notification. The `name` of each value is the stable wire
/// string stored in the database `type` column.
enum NotificationType {
  sensorDisconnected,
  noFingerDetected,
  cameraPermissionRequired,
  faceNotVisible,
  lowSensorQuality,
  sessionCompleted,
  aiSummaryReady,
  aiSummaryFailed,
  weeklyTrend;

  /// Stable string used in the DB and in deep-link payloads.
  String get wire => name;

  static NotificationType fromWire(String value) => NotificationType.values
      .firstWhere((t) => t.name == value, orElse: () => weeklyTrend);

  NotificationCategory get category => switch (this) {
        NotificationType.sensorDisconnected ||
        NotificationType.noFingerDetected ||
        NotificationType.cameraPermissionRequired ||
        NotificationType.faceNotVisible ||
        NotificationType.lowSensorQuality =>
          NotificationCategory.sensorCamera,
        NotificationType.sessionCompleted => NotificationCategory.session,
        NotificationType.aiSummaryReady ||
        NotificationType.aiSummaryFailed =>
          NotificationCategory.ai,
        NotificationType.weeklyTrend => NotificationCategory.trend,
      };
}

/// Groups notification types under the four user-facing preference switches.
enum NotificationCategory { sensorCamera, session, ai, trend }

/// A single notification, mirroring the Supabase `notifications` table. Kept
/// free of Flutter/Material imports so the logic stays unit-testable.
class AppNotification {
  final String notificationId;
  final String? userId;
  final String? sessionId;
  final NotificationType type;
  final String title;
  final String message;
  final DateTime createdAt;
  final bool isRead;
  final String? deepLink;
  final Map<String, dynamic> metadata;

  const AppNotification({
    required this.notificationId,
    required this.type,
    required this.title,
    required this.message,
    required this.createdAt,
    this.userId,
    this.sessionId,
    this.isRead = false,
    this.deepLink,
    this.metadata = const {},
  });

  /// Builds a client-side draft (no DB id yet). The id is replaced with the
  /// real uuid once the row is persisted; if it is never persisted the client
  /// id still keeps the in-app centre working.
  factory AppNotification.draft({
    required NotificationType type,
    required String title,
    required String message,
    String? userId,
    String? sessionId,
    String? deepLink,
    Map<String, dynamic> metadata = const {},
    DateTime? createdAt,
  }) {
    final now = createdAt ?? DateTime.now();
    return AppNotification(
      notificationId: '${type.name}_${now.microsecondsSinceEpoch}',
      type: type,
      title: title,
      message: message,
      userId: userId,
      sessionId: sessionId,
      deepLink: deepLink,
      metadata: metadata,
      createdAt: now,
    );
  }

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      notificationId: json['notification_id'].toString(),
      userId: json['user_id'] as String?,
      sessionId: json['session_id'] as String?,
      type: NotificationType.fromWire(json['type'] as String? ?? 'weeklyTrend'),
      title: json['title'] as String? ?? '',
      message: json['message'] as String? ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      isRead: json['is_read'] as bool? ?? false,
      deepLink: json['deep_link'] as String?,
      metadata: (json['metadata'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }

  /// Columns for an insert (the DB assigns notification_id + created_at).
  Map<String, dynamic> toInsertJson() => {
        if (userId != null) 'user_id': userId,
        if (sessionId != null) 'session_id': sessionId,
        'type': type.wire,
        'title': title,
        'message': message,
        'is_read': isRead,
        if (deepLink != null) 'deep_link': deepLink,
        'metadata': metadata,
      };

  AppNotification copyWith({bool? isRead, String? notificationId}) {
    return AppNotification(
      notificationId: notificationId ?? this.notificationId,
      userId: userId,
      sessionId: sessionId,
      type: type,
      title: title,
      message: message,
      createdAt: createdAt,
      isRead: isRead ?? this.isRead,
      deepLink: deepLink,
      metadata: metadata,
    );
  }
}
