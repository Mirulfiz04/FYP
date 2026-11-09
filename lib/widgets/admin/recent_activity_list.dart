import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/admin_dashboard_models.dart';
import '../../theme/app_theme.dart';
import '../ui_kit.dart';

/// "Recent Activity" card: the latest sessions across all users, each tappable
/// to open its Session Details. A "View All" action opens Monitor Sessions.
class RecentActivityList extends StatelessWidget {
  final List<RecentActivityItem> items;
  final ValueChanged<RecentActivityItem> onOpen;
  final VoidCallback onViewAll;

  const RecentActivityList({
    super.key,
    required this.items,
    required this.onOpen,
    required this.onViewAll,
  });

  static Color statusColor(ActivityStatus s) => switch (s) {
        ActivityStatus.live => MedsColors.greenDark,
        ActivityStatus.completed => MedsColors.blue,
        ActivityStatus.flagged => MedsColors.red,
        ActivityStatus.review => MedsColors.purple,
      };

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: MedsColors.purple.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(Icons.history,
                      size: 16, color: MedsColors.purple),
                ),
                const SizedBox(width: 9),
                const Expanded(
                  child: Text('Recent Activity',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15.5)),
                ),
                if (items.isNotEmpty)
                  TextButton(
                    onPressed: onViewAll,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 0),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('View All',
                        style: TextStyle(
                            color: MedsColors.purple,
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(0, 10, 6, 14),
              child: Text('No recent sessions yet.',
                  style: TextStyle(color: MedsColors.muted, fontSize: 13)),
            )
          else
            ...items.map((it) => _ActivityRow(item: it, onTap: () => onOpen(it))),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final RecentActivityItem item;
  final VoidCallback onTap;

  const _ActivityRow({required this.item, required this.onTap});

  bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    final color = RecentActivityList.statusColor(item.status);
    final t = item.time;
    final dateLabel = _isToday(t) ? 'Today' : DateFormat('d MMM').format(t);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 9, 6, 9),
        child: Row(
          children: [
            _Avatar(item: item, color: color),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(item.shortId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: MedsColors.muted, fontSize: 11.5)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Pill(text: item.status.label, color: color),
                const SizedBox(height: 5),
                Text(DateFormat('h:mm a').format(t),
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600)),
                Text(dateLabel,
                    style:
                        const TextStyle(color: MedsColors.muted, fontSize: 10.5)),
              ],
            ),
            const Icon(Icons.chevron_right, color: MedsColors.muted, size: 20),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final RecentActivityItem item;
  final Color color;

  const _Avatar({required this.item, required this.color});

  @override
  Widget build(BuildContext context) {
    final hasPhoto = item.avatarUrl != null && item.avatarUrl!.isNotEmpty;
    return Stack(
      children: [
        CircleAvatar(
          radius: 21,
          backgroundColor: color.withValues(alpha: 0.15),
          backgroundImage: hasPhoto ? NetworkImage(item.avatarUrl!) : null,
          child: hasPhoto
              ? null
              : Text(item.initials,
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                  color: Theme.of(context).colorScheme.surface, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}
