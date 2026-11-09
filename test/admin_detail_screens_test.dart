import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meds_flutter_no_python/models/admin_insights_model.dart';
import 'package:meds_flutter_no_python/models/insights_data.dart';
import 'package:meds_flutter_no_python/screens/admin/admin_emotion_detail_screen.dart';
import 'package:meds_flutter_no_python/screens/admin/admin_performance_detail_screen.dart';
import 'package:meds_flutter_no_python/theme/app_theme.dart';

Widget _wrap(Widget child) =>
    MaterialApp(theme: buildLightTheme(), home: child);

const _perf = SessionPerformance(
  completionRate: 88,
  completionDelta: 38,
  aiReviewedRate: 26,
  aiReviewedDelta: 26,
  avgDetectionSeconds: 5.0,
  detectionDelta: -0.3,
);

void main() {
  group('AdminPerformanceDetailScreen', () {
    testWidgets('renders the three performance metrics', (tester) async {
      await tester.pumpWidget(_wrap(const AdminPerformanceDetailScreen(
          performance: _perf, comparison: 'vs last week')));
      await tester.pumpAndSettle();

      expect(find.text('Session Performance'), findsOneWidget);
      expect(find.text('Completion Rate'), findsOneWidget);
      expect(find.text('88%'), findsOneWidget);
      expect(find.text('AI Summaries Reviewed'), findsOneWidget);
      expect(find.text('Avg Detection Time'), findsOneWidget);
      expect(find.text('5.0s'), findsOneWidget);
    });

    testWidgets('handles a missing detection time', (tester) async {
      await tester.pumpWidget(_wrap(const AdminPerformanceDetailScreen(
        performance: SessionPerformance(
          completionRate: 50,
          completionDelta: 0,
          aiReviewedRate: 0,
          aiReviewedDelta: 0,
          avgDetectionSeconds: null,
          detectionDelta: null,
        ),
        comparison: 'vs last week',
      )));
      await tester.pumpAndSettle();
      expect(find.text('—'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('does not overflow on a small screen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_wrap(const AdminPerformanceDetailScreen(
          performance: _perf, comparison: 'vs last week')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('AdminEmotionDetailScreen', () {
    testWidgets('renders the donut and a full breakdown', (tester) async {
      const emotions = [
        EmotionSlice('Neutral', 67, 41.6),
        EmotionSlice('Happy', 65, 40.4),
        EmotionSlice('Angry', 19, 11.8),
      ];
      await tester.pumpWidget(
          _wrap(const AdminEmotionDetailScreen(emotions: emotions, total: 34)));
      await tester.pumpAndSettle();

      expect(find.text('Emotion Distribution'), findsWidgets); // AppBar + card
      expect(find.text('All emotions'), findsOneWidget);
      expect(find.text('Neutral'), findsWidgets);
      expect(find.text('Happy'), findsWidgets);
    });

    testWidgets('shows an empty state when there is no data', (tester) async {
      await tester.pumpWidget(
          _wrap(const AdminEmotionDetailScreen(emotions: [], total: 0)));
      await tester.pumpAndSettle();
      expect(find.text('No emotion data'), findsOneWidget);
    });
  });
}
