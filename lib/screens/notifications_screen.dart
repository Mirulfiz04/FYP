import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/app_notification.dart';
import '../services/notification_router.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';

/// The Notification Centre: lists notifications newest→oldest, shows unread
/// state, supports mark-one / mark-all read, and routes on tap.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: notifications,
      builder: (context, _) {
        final items = notifications.items;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Notifications'),
            actions: [
              if (notifications.hasUnread)
                TextButton(
                  onPressed: notifications.markAllRead,
                  child: const Text('Mark all read'),
                ),
            ],
          ),
          body: items.isEmpty
              ? const EmptyState(
                  icon: Icons.notifications_none,
                  title: 'No notifications yet',
                  message:
                      'Session summaries, AI insights and weekly trends will '
                      'appear here.',
                  color: MedsColors.purple,
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  itemBuilder: (context, i) =>
                      _NotificationTile(item: items[i]),
                ),
        );
      },
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final AppNotification item;
  const _NotificationTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final visual = _visualFor(item.type);
    final time = _friendlyTime(item.createdAt.toLocal());

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        color: item.isRead
            ? null
            : visual.color.withValues(alpha: 0.06),
        onTap: () {
          notifications.markRead(item.notificationId);
          if (item.deepLink != null) handleDeepLink(item.deepLink);
        },
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: visual.color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(visual.icon, color: visual.color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          style: TextStyle(
                            fontWeight: item.isRead
                                ? FontWeight.w600
                                : FontWeight.bold,
                            fontSize: 14.5,
                          ),
                        ),
                      ),
                      if (!item.isRead)
                        Container(
                          width: 9,
                          height: 9,
                          decoration: const BoxDecoration(
                            color: MedsColors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(item.message,
                      style: const TextStyle(
                          fontSize: 12.5, height: 1.3, color: MedsColors.muted)),
                  if (item.metadata['evidence'] is String) ...[
                    const SizedBox(height: 4),
                    Text(item.metadata['evidence'] as String,
                        style: const TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: MedsColors.muted)),
                  ],
                  const SizedBox(height: 6),
                  Text(time,
                      style: const TextStyle(
                          fontSize: 11, color: MedsColors.muted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _friendlyTime(DateTime t) {
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('dd MMM yyyy • HH:mm').format(t);
  }
}

class _Visual {
  final IconData icon;
  final Color color;
  const _Visual(this.icon, this.color);
}

_Visual _visualFor(NotificationType type) => switch (type) {
      NotificationType.sensorDisconnected =>
        const _Visual(Icons.bluetooth_disabled, MedsColors.red),
      NotificationType.noFingerDetected =>
        const _Visual(Icons.touch_app_outlined, MedsColors.amber),
      NotificationType.cameraPermissionRequired =>
        const _Visual(Icons.no_photography_outlined, MedsColors.red),
      NotificationType.faceNotVisible =>
        const _Visual(Icons.face_retouching_off, MedsColors.amber),
      NotificationType.lowSensorQuality =>
        const _Visual(Icons.sensors_off, MedsColors.amber),
      NotificationType.sessionCompleted =>
        const _Visual(Icons.check_circle_outline, MedsColors.green),
      NotificationType.aiSummaryReady =>
        const _Visual(Icons.auto_awesome, MedsColors.purple),
      NotificationType.aiSummaryFailed =>
        const _Visual(Icons.error_outline, MedsColors.red),
      NotificationType.weeklyTrend =>
        const _Visual(Icons.insights_outlined, MedsColors.blue),
    };
