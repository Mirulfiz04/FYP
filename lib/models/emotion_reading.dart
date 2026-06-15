class EmotionReading {
  final int id;
  final DateTime createdAt;
  final String emotion;
  final double confidence;
  final int hr;
  final int spo2;
  final String sensorQuality;
  final String? userId;
  final String? sessionId;

  const EmotionReading({
    required this.id,
    required this.createdAt,
    required this.emotion,
    required this.confidence,
    required this.hr,
    required this.spo2,
    required this.sensorQuality,
    this.userId,
    this.sessionId,
  });

  factory EmotionReading.fromJson(Map<String, dynamic> json) {
    return EmotionReading(
      id: json['id'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
      emotion: json['emotion'] as String,
      confidence: (json['confidence'] as num).toDouble(),
      hr: json['hr'] as int? ?? 0,
      spo2: json['spo2'] as int? ?? 0,
      sensorQuality: json['sensor_quality'] as String? ?? 'WAITING',
      userId: json['user_id'] as String?,
      sessionId: json['session_id'] as String?,
    );
  }
}
