import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../models/insights_data.dart';
import '../../theme/app_theme.dart';
import '../ui_kit.dart';

/// "Emotion Distribution" donut: a ring of the detected emotions with the total
/// detection count in the centre, plus a legend showing percentage and count.
class EmotionDistributionCard extends StatelessWidget {
  final List<EmotionSlice> slices;
  final int total;

  /// Caption under the centre number (e.g. "Total" or "Sessions").
  final String centerLabel;

  /// When provided, a "View All Emotions" button is shown at the bottom.
  final VoidCallback? onViewAll;

  const EmotionDistributionCard({
    super.key,
    required this.slices,
    required this.total,
    this.centerLabel = 'Total',
    this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: MedsColors.coral.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.donut_large,
                    size: 16, color: MedsColors.coral),
              ),
              const SizedBox(width: 9),
              const Text('Emotion Distribution',
                  style:
                      TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5)),
            ],
          ),
          const SizedBox(height: 16),
          if (slices.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: Text('No emotion detections for this period yet.',
                    style: TextStyle(color: MedsColors.muted, fontSize: 13)),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, c) {
                final stacked = c.maxWidth < 320;
                final donut = _donut();
                final legend = _legend();
                if (stacked) {
                  return Column(children: [
                    donut,
                    const SizedBox(height: 16),
                    legend,
                  ]);
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    donut,
                    const SizedBox(width: 18),
                    Expanded(child: legend),
                  ],
                );
              },
            ),
          if (onViewAll != null) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 4),
            _ViewAllButton(onTap: onViewAll!, label: 'View All Emotions'),
          ],
        ],
      ),
    );
  }

  Widget _donut() {
    return SizedBox(
      width: 132,
      height: 132,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 38,
              startDegreeOffset: -90,
              sections: slices
                  .map((s) => PieChartSectionData(
                        value: s.count.toDouble(),
                        color: MedsColors.emotion(s.emotion),
                        radius: 20,
                        showTitle: false,
                      ))
                  .toList(),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$total',
                  style: const TextStyle(
                      fontSize: 23, fontWeight: FontWeight.w800, height: 1.0)),
              Text(centerLabel,
                  style:
                      const TextStyle(color: MedsColors.muted, fontSize: 11.5)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legend() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: slices.map(_legendRow).toList(),
    );
  }

  Widget _legendRow(EmotionSlice s) {
    final color = MedsColors.emotion(s.emotion);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(s.emotion,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: 8),
          Text('${s.percent.round()}%',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(width: 6),
          Text('(${s.count})',
              style: const TextStyle(color: MedsColors.muted, fontSize: 11.5)),
        ],
      ),
    );
  }
}

/// A full-width, tappable "View All …" footer button used by the admin cards.
class _ViewAllButton extends StatelessWidget {
  final VoidCallback onTap;
  final String label;

  const _ViewAllButton({required this.onTap, required this.label});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(label,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: MedsColors.purple,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5)),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: MedsColors.purple, size: 19),
          ],
        ),
      ),
    );
  }
}
