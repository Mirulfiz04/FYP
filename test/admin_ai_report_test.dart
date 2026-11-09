import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meds_flutter_no_python/models/ai_admin_report.dart';
import 'package:meds_flutter_no_python/screens/admin/admin_ai_report_screen.dart';
import 'package:meds_flutter_no_python/services/admin_service.dart';
import 'package:meds_flutter_no_python/services/ai_service.dart';
import 'package:meds_flutter_no_python/theme/app_theme.dart';

AdminStats _stats() => const AdminStats(
      totalUsers: 3,
      totalAdmins: 1,
      totalSessions: 34,
      activeSessions: 0,
      completedSessions: 29,
      totalReadings: 161,
      emotionCounts: {},
      emotionSampleSize: 0,
      avgSessionDuration: Duration.zero,
      perUser: [],
    );

AiAdminReport _report() => const AiAdminReport(
      executiveSummary: 'Overall the platform is healthy this period.',
      emotionalClimate: 'Mostly positive emotional patterns.',
      engagement: 'Steady session activity.',
      keyFindings: ['Engagement is stable'],
      concerns: ['Two sessions flagged'],
      recommendations: ['Keep monitoring flagged users'],
    );

Widget _wrap(Widget child) =>
    MaterialApp(theme: buildLightTheme(), home: child);

void main() {
  testWidgets('renders the on-brand report screen', (tester) async {
    await tester.pumpWidget(_wrap(AdminAiReportScreen(
      statsLoader: () async => _stats(),
      generate: (_) async => _report(),
    )));
    await tester.pumpAndSettle();

    expect(find.text('Detailed AI Report'), findsOneWidget); // renamed title
    expect(find.text('Data in this report'), findsOneWidget);
    expect(find.text('161'), findsOneWidget); // readings stat
    expect(find.text('Generate AI Report'), findsOneWidget);
  });

  testWidgets('generating shows the report sections', (tester) async {
    await tester.pumpWidget(_wrap(AdminAiReportScreen(
      statsLoader: () async => _stats(),
      generate: (_) async => _report(),
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Generate AI Report'));
    await tester.pumpAndSettle();

    expect(find.text('Executive summary'), findsOneWidget);
    expect(find.textContaining('platform is healthy'), findsOneWidget);
    expect(find.text('Recommendations'), findsOneWidget);
    expect(find.text('Regenerate'), findsOneWidget);
  });

  testWidgets('a failed generation shows the error', (tester) async {
    await tester.pumpWidget(_wrap(AdminAiReportScreen(
      statsLoader: () async => _stats(),
      generate: (_) async => throw const AiException('AI service unavailable'),
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Generate AI Report'));
    await tester.pumpAndSettle();

    expect(find.text('AI service unavailable'), findsOneWidget);
  });
}
