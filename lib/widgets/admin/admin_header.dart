import 'package:flutter/material.dart';

import '../../services/notification_service.dart';
import '../../theme/app_theme.dart';

/// A white, rounded, soft-shadowed icon button used in the admin screen headers.
class AdminHeaderButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final bool busy;
  final VoidCallback? onTap;

  const AdminHeaderButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color = MedsColors.purple,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: onTap,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              boxShadow: softShadow(context),
              color: Theme.of(context).colorScheme.surface,
            ),
            child: busy
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child:
                        CircularProgressIndicator(strokeWidth: 2.4, color: color),
                  )
                : Icon(icon, color: color, size: 21),
          ),
        ),
      ),
    );
  }
}

/// A header button with a live unread-count badge from the [notifications]
/// store (used for the Notifications action).
class AdminNotificationButton extends StatelessWidget {
  final VoidCallback onTap;
  final Color color;

  const AdminNotificationButton({
    super.key,
    required this.onTap,
    this.color = MedsColors.purple,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: notifications,
      builder: (context, _) {
        final count = notifications.unreadCount;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            AdminHeaderButton(
              icon: Icons.notifications_outlined,
              tooltip: 'Notifications',
              color: color,
              onTap: onTap,
            ),
            if (count > 0)
              Positioned(
                right: -3,
                top: -3,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
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
                        height: 1.2),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
