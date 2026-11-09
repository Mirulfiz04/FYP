import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/admin_sessions_model.dart';
import '../../theme/app_theme.dart';
import '../ui_kit.dart';

/// Colour for a session display status. Flagged uses amber so it's noticeable
/// but not alarming.
Color sessionStatusColor(ActivityStatus s) => switch (s) {
      ActivityStatus.live => MedsColors.greenDark,
      ActivityStatus.completed => MedsColors.blue,
      ActivityStatus.flagged => MedsColors.amber,
      ActivityStatus.review => MedsColors.purple,
    };

IconData _statusIcon(ActivityStatus s) => switch (s) {
      ActivityStatus.live => Icons.circle,
      ActivityStatus.completed => Icons.check_circle_outline,
      ActivityStatus.flagged => Icons.flag_outlined,
      ActivityStatus.review => Icons.visibility_outlined,
    };

IconData _emotionIcon(String emotion) => switch (emotion) {
      'Happy' => Icons.sentiment_very_satisfied,
      'Surprise' => Icons.sentiment_satisfied_alt,
      'Neutral' => Icons.sentiment_neutral,
      'Sad' => Icons.sentiment_dissatisfied,
      'Fear' => Icons.sentiment_dissatisfied,
      'Angry' => Icons.sentiment_very_dissatisfied,
      'Disgust' => Icons.sentiment_very_dissatisfied,
      _ => Icons.sentiment_neutral,
    };

String _fmtDuration(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return d.inHours > 0 ? '${d.inHours}h ${m}m' : '${m}m ${s}s';
}

/// A Monitor Sessions list card: avatar (with status dot), user, date/time,
/// emotion, heart rate, duration, a status badge and a chevron to open details.
class MonitorSessionCard extends StatelessWidget {
  final MonitorSession item;
  final VoidCallback onOpen;

  const MonitorSessionCard({super.key, required this.item, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final color = sessionStatusColor(item.status);
    final hasPhoto = item.avatarUrl != null && item.avatarUrl!.isNotEmpty;
    final emotionColor = MedsColors.emotion(item.emotion);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        onTap: onOpen,
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _avatar(context, color, hasPhoto),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(item.userName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15.5)),
                      ),
                      const SizedBox(width: 8),
                      _StatusBadge(status: item.status, color: color),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 14,
                    runSpacing: 4,
                    children: [
                      _meta(Icons.calendar_today_outlined, MedsColors.muted,
                          DateFormat('d MMM yyyy').format(item.start)),
                      _meta(Icons.schedule, MedsColors.muted,
                          DateFormat('h:mm a').format(item.start)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 14,
                    runSpacing: 4,
                    children: [
                      _meta(_emotionIcon(item.emotion), emotionColor,
                          item.emotion),
                      _meta(Icons.favorite, MedsColors.coral,
                          item.avgBpm == 0 ? '—' : '${item.avgBpm} BPM'),
                      _meta(Icons.timer_outlined, MedsColors.blue,
                          _fmtDuration(item.duration)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, color: MedsColors.muted),
          ],
        ),
      ),
    );
  }

  Widget _avatar(BuildContext context, Color color, bool hasPhoto) {
    return SizedBox(
      width: 50,
      height: 50,
      child: Stack(
        children: [
          CircleAvatar(
            radius: 25,
            backgroundColor: color.withValues(alpha: 0.15),
            backgroundImage: hasPhoto ? NetworkImage(item.avatarUrl!) : null,
            child: hasPhoto
                ? null
                : Text(item.initials,
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                    color: Theme.of(context).colorScheme.surface, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _meta(IconData icon, Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(text,
            style: const TextStyle(fontSize: 12.5, color: MedsColors.lightText)),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final ActivityStatus status;
  final Color color;

  const _StatusBadge({required this.status, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_statusIcon(status), size: status == ActivityStatus.live ? 9 : 13,
              color: color),
          const SizedBox(width: 5),
          Text(status.label,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.bold, fontSize: 11.5)),
        ],
      ),
    );
  }
}
