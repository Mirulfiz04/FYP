import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../ui_kit.dart';
import 'dashboard_metric_card.dart' show SkeletonBox;

/// A summary metric card for the Insights screen: a tinted icon chip on top,
/// then the label, a large value (with an optional small unit) and a [footer]
/// supplied by the caller (a trend pill or a caption).
class InsightMetricCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String? unit;
  final Widget footer;

  const InsightMetricCard({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.footer,
    this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 12.5, color: MedsColors.muted, height: 1.1),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(value,
                    style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        height: 1.0)),
                if (unit != null) ...[
                  const SizedBox(width: 4),
                  Text(unit!,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: MedsColors.muted)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          footer,
        ],
      ),
    );
  }
}

/// A small "42% of sessions"-style caption used by the Dominant Emotion card.
class MetricCaption extends StatelessWidget {
  final String highlight;
  final String text;
  final Color color;

  const MetricCaption({
    super.key,
    required this.highlight,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(highlight,
            style: TextStyle(
                color: color, fontWeight: FontWeight.bold, fontSize: 12)),
        const SizedBox(width: 5),
        Flexible(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: MedsColors.muted, fontSize: 11.5)),
        ),
      ],
    );
  }
}

/// Skeleton placeholder shaped like an [InsightMetricCard].
class InsightMetricSkeleton extends StatelessWidget {
  const InsightMetricSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: const [
          SkeletonBox(width: 39, height: 39, radius: null),
          SizedBox(height: 14),
          SkeletonBox(width: 80, height: 10),
          SizedBox(height: 10),
          SkeletonBox(width: 56, height: 22),
          SizedBox(height: 10),
          SkeletonBox(width: 100, height: 10),
        ],
      ),
    );
  }
}
