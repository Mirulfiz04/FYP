/// An AI-generated, platform-wide analytics report built from aggregated admin
/// statistics by [AiService.generateAdminReport]. Powers the one-click admin
/// AI Report Generator.
class AiAdminReport {
  /// A short executive summary of the platform's current state.
  final String executiveSummary;

  /// How users are feeling overall (the emotional climate).
  final String emotionalClimate;

  /// Usage / engagement narrative (sessions, activity).
  final String engagement;

  /// The most important data points worth highlighting.
  final List<String> keyFindings;

  /// Things that may need attention.
  final List<String> concerns;

  /// Practical, prioritized next steps for the admin.
  final List<String> recommendations;

  const AiAdminReport({
    required this.executiveSummary,
    required this.emotionalClimate,
    required this.engagement,
    required this.keyFindings,
    required this.concerns,
    required this.recommendations,
  });

  static List<String> _stringList(dynamic v) =>
      (v as List?)?.map((e) => e.toString()).toList() ?? const [];

  factory AiAdminReport.fromJson(Map<String, dynamic> json) {
    return AiAdminReport(
      executiveSummary: json['executiveSummary'] as String? ?? '',
      emotionalClimate: json['emotionalClimate'] as String? ?? '',
      engagement: json['engagement'] as String? ?? '',
      keyFindings: _stringList(json['keyFindings']),
      concerns: _stringList(json['concerns']),
      recommendations: _stringList(json['recommendations']),
    );
  }

  /// A plain-text rendering of the report so an admin can copy / export it.
  /// [header] is prepended (e.g. a title + the data the report was built from).
  String toPlainText({String header = ''}) {
    String section(String title, List<String> items) {
      if (items.isEmpty) return '';
      final lines = items.map((e) => '  - $e').join('\n');
      return '\n$title\n$lines\n';
    }

    final buf = StringBuffer();
    if (header.isNotEmpty) buf.writeln(header);
    buf.writeln('EXECUTIVE SUMMARY');
    buf.writeln(executiveSummary);
    buf.writeln('\nEMOTIONAL CLIMATE');
    buf.writeln(emotionalClimate);
    buf.writeln('\nENGAGEMENT');
    buf.writeln(engagement);
    buf.write(section('KEY FINDINGS', keyFindings));
    buf.write(section('CONCERNS', concerns));
    buf.write(section('RECOMMENDATIONS', recommendations));
    return buf.toString().trimRight();
  }
}
