import 'package:flutter/material.dart';

import '../models/user_profile.dart';

const LinearGradient _gradient = LinearGradient(
  colors: [Color(0xFF8B7CF6), Color(0xFF6A5AE0)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);
const Color _accent = Color(0xFF6A5AE0);

/// Purple gradient profile header: avatar (image or initials), name, email and
/// an Edit Profile button.
class ProfileHeaderCard extends StatelessWidget {
  final UserProfile profile;
  final VoidCallback onEdit;

  const ProfileHeaderCard({
    super.key,
    required this.profile,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final url = profile.avatarUrl;
    final hasAvatar = url != null && url.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: _gradient,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: _accent.withValues(alpha: 0.30),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Semantics(
            label: 'Profile picture',
            child: CircleAvatar(
              radius: 40,
              backgroundColor: Colors.white.withValues(alpha: 0.25),
              backgroundImage: hasAvatar ? NetworkImage(url) : null,
              child: hasAvatar
                  ? null
                  : Text(
                      profile.initials,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.bold),
                    ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.displayLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  profile.email ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 13),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 36,
                  child: FilledButton.icon(
                    onPressed: onEdit,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.22),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Edit Profile'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
