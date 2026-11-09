import 'package:flutter/material.dart';

import '../../models/insights_data.dart';
import '../../theme/app_theme.dart';
import '../../widgets/admin/emotion_distribution_card.dart';
import '../../widgets/ui_kit.dart';

/// On-brand detail screen for "Emotion Distribution" — the donut plus a full,
/// ranked breakdown of every detected emotion with its share and count.
class AdminEmotionDetailScreen extends StatelessWidget {
  final List<EmotionSlice> emotions;
  final int total;

  const AdminEmotionDetailScreen({
    super.key,
    required this.emotions,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final detections = emotions.fold<int>(0, (a, s) => a + s.count);
    return Scaffold(
      appBar: AppBar(title: const Text('Emotion Distribution')),
      body: emotions.isEmpty
          ? const EmptyState(
              icon: Icons.donut_large,
              color: MedsColors.coral,
              title: 'No emotion data',
              message: 'There are no emotion detections for this period yet.',
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'How detected emotions are distributed across sessions for the '
                  'selected period.',
                  style: TextStyle(
                      color: MedsColors.muted, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 16),
                EmotionDistributionCard(
                  slices: emotions,
                  total: total,
                  centerLabel: 'Sessions',
                ),
                const SizedBox(height: 16),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('All emotions',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15.5)),
                      const SizedBox(height: 14),
                      ...emotions.map(_row),
                      const SizedBox(height: 6),
                      Text('Based on $detections detections',
                          style: const TextStyle(
                              color: MedsColors.muted, fontSize: 11.5)),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _row(EmotionSlice s) {
    final color = MedsColors.emotion(s.emotion);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                  width: 10,
                  height: 10,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 9),
              Expanded(
                child: Text(s.emotion,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13.5)),
              ),
              const SizedBox(width: 8),
              Text('${s.percent.round()}%',
                  style: TextStyle(
                      color: color, fontWeight: FontWeight.bold, fontSize: 13.5)),
              const SizedBox(width: 6),
              Text('(${s.count})',
                  style:
                      const TextStyle(color: MedsColors.muted, fontSize: 11.5)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (s.percent / 100).clamp(0.0, 1.0),
              minHeight: 7,
              backgroundColor: color.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }
}
