/// Session-level summary numbers computed during a live session and saved to
/// the `detection_sessions` row when the session ends.
class SessionAggregates {
  final String dominantEmotion;
  final double averageConfidence;
  final int? baselineBpm;
  final int averageBpm;
  final int minimumBpm;
  final int maximumBpm;
  final String finalState;
  final String cameraQuality; // Good | Fair | Poor
  final String sensorQuality; // Good | Fair | Poor
  final int readingsSaved;

  const SessionAggregates({
    required this.dominantEmotion,
    required this.averageConfidence,
    required this.baselineBpm,
    required this.averageBpm,
    required this.minimumBpm,
    required this.maximumBpm,
    required this.finalState,
    required this.cameraQuality,
    required this.sensorQuality,
    required this.readingsSaved,
  });

  Map<String, dynamic> toUpdateJson() => {
        'dominant_emotion': dominantEmotion,
        'avg_confidence': averageConfidence,
        'baseline_bpm': baselineBpm,
        'average_bpm': averageBpm,
        'min_bpm': minimumBpm,
        'max_bpm': maximumBpm,
        'final_state': finalState,
        'camera_quality': cameraQuality,
        'sensor_quality': sensorQuality,
      };
}
