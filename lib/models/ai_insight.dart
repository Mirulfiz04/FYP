/// An AI-generated emotional-wellness insight for one user, built from their
/// emotion + heart-rate readings by [AiService].
class AiInsight {
  /// A short, warm summary of how the user has been feeling.
  final String emotionalSummary;

  /// Overall stress level: Low | Moderate | Elevated | High.
  final String stressLevel;

  /// How the user's emotional / physiological state appears to be changing.
  final String trendAnalysis;

  /// A few short, practical, personalized recommendations.
  final List<String> recommendations;

  const AiInsight({
    required this.emotionalSummary,
    required this.stressLevel,
    required this.trendAnalysis,
    required this.recommendations,
  });

  factory AiInsight.fromJson(Map<String, dynamic> json) {
    return AiInsight(
      emotionalSummary: json['emotionalSummary'] as String? ?? '',
      stressLevel: json['stressLevel'] as String? ?? 'Moderate',
      trendAnalysis: json['trendAnalysis'] as String? ?? '',
      recommendations: (json['recommendations'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'emotionalSummary': emotionalSummary,
        'stressLevel': stressLevel,
        'trendAnalysis': trendAnalysis,
        'recommendations': recommendations,
      };
}
