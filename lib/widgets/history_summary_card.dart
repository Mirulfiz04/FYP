import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../viewmodels/history_view_model.dart';

/// Compact 3-up summary for the History screen (Total Sessions / Avg BPM /
/// Most Frequent Emotion). Recomputes from whatever is currently filtered.
class HistorySummaryCard extends StatelessWidget {
  final HistorySummary summary;
  const HistorySummaryCard({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: MedsColors.purple.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: MedsColors.purple.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: _cell(
              icon: Icons.event_note,
              color: MedsColors.purple,
              label: 'Total Sessions',
              value: '${summary.totalSessions}',
              sub: 'This filter',
            ),
          ),
          _divider(context),
          Expanded(
            child: _cell(
              icon: Icons.favorite,
              color: MedsColors.pink,
              label: 'Avg. BPM',
              value: summary.averageBpm > 0 ? '${summary.averageBpm}' : '--',
              sub: 'This filter',
            ),
          ),
          _divider(context),
          Expanded(
            child: _cell(
              icon: Icons.mood,
              color: MedsColors.greenDark,
              label: 'Most Frequent',
              value: summary.topEmotion,
              sub: summary.totalSessions > 0
                  ? '${summary.topEmotionPercent}% of time'
                  : '—',
              small: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider(BuildContext context) => Container(
        width: 1,
        height: 46,
        color: Theme.of(context).dividerColor,
        margin: const EdgeInsets.symmetric(horizontal: 6),
      );

  Widget _cell({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
    required String sub,
    bool small = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(height: 7),
        Text(label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10.5, color: MedsColors.muted)),
        const SizedBox(height: 2),
        Text(value,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: small ? 14 : 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 1),
        Text(sub,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, color: MedsColors.muted)),
      ],
    );
  }
}
