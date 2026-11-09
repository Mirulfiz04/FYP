/// An AI-generated emotional-trend report built from time-bucketed readings
/// (weekly or monthly) by [AiService.generateTrendAnalysis]. Used by the admin
/// AI Trend Analysis dashboard.
class AiTrendReport {
  /// A one-line takeaway describing the overall direction of the trend.
  final String headline;

  /// A paragraph analysing how the emotional / physiological picture changes
  /// across the periods.
  final String analysis;

  /// What is going well across the periods.
  final List<String> positives;

  /// What to keep an eye on.
  final List<String> concerns;

  /// Short, practical follow-up actions.
  final List<String> recommendations;

  const AiTrendReport({
    required this.headline,
    required this.analysis,
    required this.positives,
    required this.concerns,
    required this.recommendations,
  });

  static List<String> _stringList(dynamic v) =>
      (v as List?)?.map((e) => e.toString()).toList() ?? const [];

  factory AiTrendReport.fromJson(Map<String, dynamic> json) {
    return AiTrendReport(
      headline: json['headline'] as String? ?? '',
      analysis: json['analysis'] as String? ?? '',
      positives: _stringList(json['positives']),
      concerns: _stringList(json['concerns']),
      recommendations: _stringList(json['recommendations']),
    );
  }
}
