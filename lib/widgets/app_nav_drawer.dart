import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

const Color _accent = Color(0xFF6A5AE0);

/// Shared navigation drawer used by the dashboard tabs. Pure presentation —
/// the host wires the callbacks to tab switches / navigation.
class AppNavDrawer extends StatelessWidget {
  final String? name;
  final String? avatarUrl;
  final ValueChanged<int> onOpenTab; // 0 Home · 1 History · 2 Insights · 3 Profile
  final VoidCallback onNotifications;
  final VoidCallback onSignOut;

  const AppNavDrawer({
    super.key,
    required this.name,
    required this.avatarUrl,
    required this.onOpenTab,
    required this.onNotifications,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final hasAvatar = (avatarUrl ?? '').isNotEmpty;
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: _accent.withValues(alpha: 0.15),
                    backgroundImage: hasAvatar ? NetworkImage(avatarUrl!) : null,
                    child: hasAvatar
                        ? null
                        : const Icon(Icons.person, color: _accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      name ?? 'MEDS user',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            _item(context, Icons.home_outlined, 'Home', () => onOpenTab(0)),
            _item(context, Icons.history_outlined, 'History', () => onOpenTab(1)),
            _item(context, Icons.insights_outlined, 'Insights', () => onOpenTab(2)),
            _item(context, Icons.notifications_outlined, 'Notifications',
                onNotifications),
            _item(context, Icons.settings_outlined, 'Settings', () => onOpenTab(3)),
            const Spacer(),
            const Divider(height: 1),
            _item(context, Icons.logout, 'Sign out', onSignOut,
                color: MedsColors.red),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _item(BuildContext context, IconData icon, String label,
      VoidCallback onTap,
      {Color? color}) {
    return ListTile(
      leading: Icon(icon, color: color ?? _accent),
      title: Text(label,
          style: TextStyle(
              color: color, fontWeight: FontWeight.w500, fontSize: 14.5)),
      onTap: () {
        Navigator.pop(context); // close the drawer first
        onTap();
      },
    );
  }
}
