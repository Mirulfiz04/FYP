import 'emotion_result.dart';

/// Physiological arousal level derived from heart rate vs the session baseline.
enum Arousal { low, normal, elevated, high }

/// The fused, multimodal read-out: a smoothed + heart-rate-corroborated facial
/// emotion, plus a combined wellbeing state from the valence (face) × arousal
/// (HR) model.
class MultimodalResult {
  /// Smoothed + HR-adjusted emotion (still one of the 7 facial classes).
  final EmotionResult emotion;
  final Arousal arousal;

  /// Current HR minus the session baseline (0 until the baseline is ready).
  final int hrDelta;
  final bool baselineReady;

  /// The effective resting baseline currently used for arousal. It adapts down
  /// during the session toward the user's sustained resting rate, so a baseline
  /// captured while tense self-corrects. Null until ready.
  final int? baselineBpm;

  /// Calm / Content / Excited / Stressed / Down / Alert / Relaxed.
  final String wellbeing;
  final String wellbeingEmoji;

  /// -1 (very negative) .. +1 (very positive).
  final double valence;

  const MultimodalResult({
    required this.emotion,
    required this.arousal,
    required this.hrDelta,
    required this.baselineReady,
    this.baselineBpm,
    required this.wellbeing,
    required this.wellbeingEmoji,
    required this.valence,
  });

  String get arousalLabel => switch (arousal) {
        Arousal.low => 'Low',
        Arousal.normal => 'Normal',
        Arousal.elevated => 'Elevated',
        Arousal.high => 'High',
      };
}
