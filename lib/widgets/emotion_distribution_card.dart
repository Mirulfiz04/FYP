import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/session_analytics.dart';
import '../theme/app_theme.dart';
import 'ui_kit.dart';

const Color _accent = Color(0xFF6A5AE0);

/// Emotion Distribution: a donut of the session's emotions + a legend, with a
/// "View details" action to open the full log.
class EmotionDistributionCard extends StatelessWidget {
  final List<EmotionShare> distribution;
  final int totalReadings;

  /// When null, the "View details" link is hidden.
  final VoidCallback? onViewDetails;

  const EmotionDistributionCard({
    super.key,
    required this.distribution,
    required this.totalReadings,
    this.onViewDetails,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.donut_large, color: _accent, size: 18),
              const SizedBox(width: 8),
              const Text('Emotion Distribution',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const Spacer(),
              if (onViewDetails != null)
                TextButton(
                  onPressed: onViewDetails,
                  style: TextButton.styleFrom(
                      foregroundColor: _accent,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 0),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('View details', style: TextStyle(fontSize: 12.5)),
                    Icon(Icons.chevron_right, size: 16),
                  ]),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (distribution.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text('No emotion readings for this session.',
                  style: TextStyle(color: MedsColors.muted, fontSize: 13)),
            )
          else
            Row(
              children: [
                SizedBox(
                  width: 116,
                  height: 116,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PieChart(PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 34,
                        sections: distribution
                            .map((s) => PieChartSectionData(
                                  value: s.count.toDouble(),
                                  color: MedsColors.emotion(s.emotion),
                                  radius: 18,
                                  showTitle: false,
                                ))
                            .toList(),
                      )),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('$totalReadings',
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.bold)),
                          const Text('Readings',
                              style: TextStyle(
                                  fontSize: 10.5, color: MedsColors.muted)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    children: [
                      for (final s in distribution.take(7)) _legendRow(s),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _legendRow(EmotionShare s) {
    final color = MedsColors.emotion(s.emotion);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        children: [
          Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(s.emotion,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5)),
          ),
          Text('${s.percent.round()}%',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 12.5)),
          const SizedBox(width: 6),
          Text('(${s.count})',
              style: const TextStyle(color: MedsColors.muted, fontSize: 11.5)),
        ],
      ),
    );
  }
}
