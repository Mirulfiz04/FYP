import 'package:flutter/material.dart';

import '../models/insights_data.dart';
import '../theme/app_theme.dart';
import 'ui_kit.dart';

const Color _accent = Color(0xFF6A5AE0);

/// Weekly Overview: Best Day (lowest stress) + Highest Stress Period. Only
/// shows values when there are enough valid sessions.
class WeeklyOverviewCard extends StatelessWidget {
  final InsightsData data;
  final VoidCallback onOpenTrends;

  const WeeklyOverviewCard({
    super.key,
    required this.data,
    required this.onOpenTrends,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: data.enoughForInsight ? onOpenTrends : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Weekly Overview',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 14),
          if (!data.enoughForInsight)
            const Text(
              'Complete more valid sessions to see your best day and highest '
              'stress period.',
              style: TextStyle(color: MedsColors.muted, fontSize: 13),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _block(
                    icon: Icons.verified,
                    color: MedsColors.greenDark,
                    label: 'Best Day',
                    value: data.bestDay ?? '—',
                    sub: data.bestDayStress != null
                        ? 'Lowest stress · ${data.bestDayStress} / 5'
                        : '',
                  ),
                ),
                Container(
                    width: 1,
                    height: 56,
                    color: Theme.of(context).dividerColor,
                    margin: const EdgeInsets.symmetric(horizontal: 6)),
                Expanded(
                  child: _block(
                    icon: Icons.assignment_late_outlined,
                    color: MedsColors.coral,
                    label: 'Highest Stress Period',
                    value: data.highestStress?.day ?? '—',
                    sub: data.highestStress != null
                        ? '${data.highestStress!.partOfDay} · ${data.highestStress!.rangeLabel}'
                        : '',
                    trailingChevron: true,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _block({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
    required String sub,
    bool trailingChevron = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      color: MedsColors.muted, fontSize: 11.5)),
              const SizedBox(height: 2),
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15.5)),
              if (sub.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(sub,
                    style: const TextStyle(
                        color: MedsColors.muted, fontSize: 11)),
              ],
            ],
          ),
        ),
        if (trailingChevron)
          const Icon(Icons.chevron_right, color: _accent, size: 18),
      ],
    );
  }
}

/// Emotional Pattern card — a short plain-language pattern with a tap-through
/// to a more detailed trends view.
class EmotionalPatternCard extends StatelessWidget {
  final String pattern;
  final VoidCallback onTap;

  const EmotionalPatternCard({
    super.key,
    required this.pattern,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.insights, color: _accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Emotional Pattern',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 3),
                Text(pattern,
                    style: const TextStyle(
                        color: MedsColors.muted, fontSize: 12.5, height: 1.35)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: _accent),
        ],
      ),
    );
  }
}
