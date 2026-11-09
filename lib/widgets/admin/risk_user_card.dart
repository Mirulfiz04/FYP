import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/admin_insights_model.dart';
import '../../theme/app_theme.dart';
import '../ui_kit.dart';

/// "Top At-Risk Users" card: a short, ranked list of users whose recent
/// sessions show elevated stress or heart-rate indicators.
class TopAtRiskUsersCard extends StatelessWidget {
  final List<RiskUser> users;
  final ValueChanged<RiskUser> onOpenUser;
  final VoidCallback onViewAll;

  const TopAtRiskUsersCard({
    super.key,
    required this.users,
    required this.onOpenUser,
    required this.onViewAll,
  });

  static Color riskColor(RiskLevel r) => switch (r) {
        RiskLevel.high => MedsColors.red,
        RiskLevel.elevated => MedsColors.amber,
        RiskLevel.low => MedsColors.greenDark,
      };

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: MedsColors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.shield_outlined,
                    size: 16, color: MedsColors.red),
              ),
              const SizedBox(width: 9),
              const Expanded(
                child: Text('Top At-Risk Users',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5)),
              ),
              if (users.isNotEmpty)
                _LinkButton(label: 'View all', onTap: onViewAll),
            ],
          ),
          const SizedBox(height: 6),
          if (users.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('No at-risk users in this period.',
                  style: TextStyle(color: MedsColors.muted, fontSize: 13)),
            )
          else ...[
            ...users.map((u) => _RiskRow(user: u, onTap: () => onOpenUser(u))),
            const SizedBox(height: 4),
            const Divider(height: 1),
            const SizedBox(height: 4),
            Center(
              child: _LinkButton(label: 'View All Users', onTap: onViewAll),
            ),
          ],
        ],
      ),
    );
  }
}

class _RiskRow extends StatelessWidget {
  final RiskUser user;
  final VoidCallback onTap;

  const _RiskRow({required this.user, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = TopAtRiskUsersCard.riskColor(user.risk);
    final hasPhoto = user.avatarUrl != null && user.avatarUrl!.isNotEmpty;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: color.withValues(alpha: 0.15),
              backgroundImage: hasPhoto ? NetworkImage(user.avatarUrl!) : null,
              child: hasPhoto
                  ? null
                  : Text(user.initials,
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(
                    'Last: ${user.indicator} • ${DateFormat('h:mm a').format(user.time)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(color: MedsColors.muted, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Pill(text: user.risk.label, color: color),
            const Icon(Icons.chevron_right, color: MedsColors.muted, size: 20),
          ],
        ),
      ),
    );
  }
}

class _LinkButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _LinkButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: const Size(0, 0),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label,
          style: const TextStyle(
              color: MedsColors.purple,
              fontWeight: FontWeight.w600,
              fontSize: 13)),
    );
  }
}
