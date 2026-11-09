import 'package:flutter/material.dart';

import '../screens/notifications_screen.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';

/// A bell icon with an unread-count badge for the home dashboard AppBar.
/// Rebuilds automatically as the [notifications] store changes.
class NotificationBell extends StatelessWidget {
  final Color? iconColor;
  const NotificationBell({super.key, this.iconColor});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: notifications,
      builder: (context, _) {
        final count = notifications.unreadCount;
        return Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              icon: Icon(Icons.notifications_outlined, color: iconColor),
              tooltip: 'Notifications',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const NotificationsScreen()),
              ),
            ),
            if (count > 0)
              Positioned(
                right: 6,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  constraints:
                      const BoxConstraints(minWidth: 18, minHeight: 18),
                  decoration: BoxDecoration(
                    color: MedsColors.red,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Text(
                    count > 9 ? '9+' : '$count',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
