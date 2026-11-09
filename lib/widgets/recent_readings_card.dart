import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/emotion_reading.dart';
import '../theme/app_theme.dart';
import 'ui_kit.dart';

const Color _accent = Color(0xFF6A5AE0);

/// Shows the latest few readings (not the full log). [readings] should already
/// be newest-first.
class RecentReadingsCard extends StatelessWidget {
  final List<EmotionReading> readings;
  final VoidCallback onViewFullLogs;

  const RecentReadingsCard({
    super.key,
    required this.readings,
    required this.onViewFullLogs,
  });

  static const _validHr = {'GOOD', 'HOLDING HR'};

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.list_alt, color: _accent, size: 18),
              const SizedBox(width: 8),
              const Text('Recent Readings',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const Spacer(),
              TextButton(
                onPressed: onViewFullLogs,
                style: TextButton.styleFrom(
                    foregroundColor: _accent,
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('View full logs', style: TextStyle(fontSize: 12.5)),
                  Icon(Icons.chevron_right, size: 16),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (readings.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('No readings recorded for this session.',
                  style: TextStyle(color: MedsColors.muted, fontSize: 13)),
            )
          else
            ...readings.map(_row),
        ],
      ),
    );
  }

  Widget _row(EmotionReading r) {
    final color = MedsColors.emotion(r.emotion);
    final validHr = r.hr > 0 && _validHr.contains(r.sensorQuality);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(DateFormat('HH:mm:ss').format(r.createdAt.toLocal()),
                style: const TextStyle(color: MedsColors.muted, fontSize: 11.5)),
          ),
          Text(MedsColors.emoji(r.emotion), style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 6),
          SizedBox(
            width: 62,
            child: Text(r.emotion,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${r.confidence.round()}%',
                    style: const TextStyle(fontSize: 11.5)),
                const SizedBox(height: 3),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (r.confidence / 100).clamp(0, 1),
                    minHeight: 4,
                    backgroundColor: color.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.favorite,
                  size: 13, color: validHr ? MedsColors.pink : MedsColors.muted),
              const SizedBox(width: 4),
              Text(validHr ? '${r.hr} BPM' : 'Not available',
                  style: TextStyle(
                      fontSize: 11.5,
                      color: validHr ? null : MedsColors.muted)),
            ],
          ),
        ],
      ),
    );
  }
}
