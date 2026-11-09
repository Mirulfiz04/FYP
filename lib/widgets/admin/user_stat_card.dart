import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../ui_kit.dart';

/// A compact, fixed-width summary card for the Manage Users header
/// (Total / Active / Inactive / Blocked). Designed to sit in a horizontally
/// scrollable row so it never overflows on narrow phones.
class UserStatCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  final double width;

  const UserStatCard({
    super.key,
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    this.width = 116,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: AppCard(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 10),
            Text(value,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800, height: 1.0)),
            const SizedBox(height: 4),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: MedsColors.muted, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
