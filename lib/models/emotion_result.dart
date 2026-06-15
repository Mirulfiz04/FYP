class EmotionResult {
  final String label;
  final double confidence;
  final List<double> probabilities;

  const EmotionResult({
    required this.label,
    required this.confidence,
    required this.probabilities,
  });

  static const empty = EmotionResult(
    label: 'Detecting...',
    confidence: 0,
    probabilities: [],
  );
}
