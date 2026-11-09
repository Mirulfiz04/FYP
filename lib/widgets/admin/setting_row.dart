import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'user_badges.dart' show TintBadge;

/// A reusable settings menu row: tinted icon, title, subtitle, an optional
/// trailing widget (e.g. a status badge) and a chevron, with ripple feedback.
class SettingRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback onTap;
  final bool danger;

  const SettingRow({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final titleColor = danger ? MedsColors.red : null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: color, size: 21),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: titleColor)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: MedsColors.muted, fontSize: 12.5)),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ],
            const SizedBox(width: 6),
            Icon(Icons.chevron_right,
                color: danger ? MedsColors.red : MedsColors.muted, size: 22),
          ],
        ),
      ),
    );
  }
}

/// A rounded card grouping several [SettingRow]s, with inset dividers between
/// them — the standard "settings group" look.
class SettingsGroupCard extends StatelessWidget {
  final List<Widget> children;
  final Color? color;

  const SettingsGroupCard({super.key, required this.children, this.color});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i < children.length - 1) {
        rows.add(const Divider(height: 1, indent: 72, endIndent: 14));
      }
    }
    return Container(
      decoration: BoxDecoration(
        color: color ?? Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: dark ? Border.all(color: Theme.of(context).dividerColor) : null,
        boxShadow: softShadow(context),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(children: rows),
      ),
    );
  }
}

/// A small green/coloured status badge (e.g. "Enabled") for a settings row.
class SettingBadge extends StatelessWidget {
  final String text;
  final Color color;

  const SettingBadge({super.key, required this.text, required this.color});

  @override
  Widget build(BuildContext context) => TintBadge(text: text, color: color);
}
