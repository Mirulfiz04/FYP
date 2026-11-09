import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'ui_kit.dart';

const Color _accent = Color(0xFF6A5AE0);

/// A rounded list card for a Profile menu option: tinted leading icon, title,
/// optional subtitle/trailing, and a chevron. Large touch target + semantics.
class ProfileMenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? color;
  final Widget? trailing;
  final VoidCallback onTap;

  const ProfileMenuItem({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.color,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? _accent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        button: true,
        label: title,
        child: AppCard(
          onTap: onTap,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: c),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 15)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!,
                          style: const TextStyle(
                              color: MedsColors.muted, fontSize: 12)),
                    ],
                  ],
                ),
              ),
              trailing ??
                  const Icon(Icons.chevron_right, color: MedsColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
