import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/user_profile.dart';
import '../../theme/app_theme.dart';
import '../ui_kit.dart';
import 'user_badges.dart';

/// A single user row on the Manage Users list: avatar, name, email, join date,
/// role + status badges and a three-dot action menu.
class UserListCard extends StatelessWidget {
  final UserProfile user;
  final bool isSelf;
  final VoidCallback onTap;
  final VoidCallback onMenu;

  const UserListCard({
    super.key,
    required this.user,
    required this.isSelf,
    required this.onTap,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    final hasPhoto = user.avatarUrl != null && user.avatarUrl!.isNotEmpty;
    final accent = roleColor(user.role);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: accent.withValues(alpha: 0.15),
              backgroundImage: hasPhoto ? NetworkImage(user.avatarUrl!) : null,
              child: hasPhoto
                  ? null
                  : Text(user.initials,
                      style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          user.displayLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15.5),
                        ),
                      ),
                      if (isSelf)
                        const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Text('you',
                              style: TextStyle(
                                  color: MedsColors.muted, fontSize: 11)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(user.email ?? '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: MedsColors.muted, fontSize: 12.5)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today_outlined,
                          size: 12.5, color: MedsColors.muted),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          user.createdAt != null
                              ? 'Joined ${DateFormat('d MMM yyyy').format(user.createdAt!.toLocal())}'
                              : 'Join date unknown',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: MedsColors.muted, fontSize: 11.5),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                RoleBadge(role: user.role),
                const SizedBox(height: 6),
                StatusBadge(status: user.status),
              ],
            ),
            SizedBox(
              width: 28,
              child: IconButton(
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.more_vert, color: MedsColors.muted),
                tooltip: 'Actions',
                onPressed: onMenu,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
