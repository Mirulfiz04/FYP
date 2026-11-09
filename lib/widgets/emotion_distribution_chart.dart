import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/insights_data.dart';
import '../theme/app_theme.dart';
import 'ui_kit.dart';

/// Emotion Distribution card: a donut chart of the valid facial detections plus
/// a legend (emoji + emotion + percentage). Categories with no data are simply
/// absent from [slices].
class EmotionDistributionChart extends StatelessWidget {
  final List<EmotionSlice> slices;
  final int totalDetections;

  const EmotionDistributionChart({
    super.key,
    required this.slices,
    required this.totalDetections,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Emotion Distribution',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 14),
          if (slices.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text('No valid facial-emotion results yet.',
                  style: TextStyle(color: MedsColors.muted, fontSize: 13)),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 120,
                  height: 120,
                  child: PieChart(PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 32,
                    sections: slices
                        .map((s) => PieChartSectionData(
                              value: s.count.toDouble(),
                              color: MedsColors.emotion(s.emotion),
                              radius: 22,
                              showTitle: false,
                            ))
                        .toList(),
                  )),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ...slices.take(5).map(_legendRow),
                      const SizedBox(height: 6),
                      Text('$totalDetections valid detections',
                          style: const TextStyle(
                              color: MedsColors.muted, fontSize: 11.5)),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _legendRow(EmotionSlice s) {
    final color = MedsColors.emotion(s.emotion);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18), shape: BoxShape.circle),
            child: Center(
                child: Text(MedsColors.emoji(s.emotion),
                    style: const TextStyle(fontSize: 12))),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(s.emotion,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ),
          Text('${s.percent.round()}%',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}
