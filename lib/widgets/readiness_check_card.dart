import 'package:flutter/material.dart';

import 'ui_kit.dart';

const Color _accent = Color(0xFF6A5AE0);

/// A numbered readiness section (e.g. "1. Camera") wrapping a list of check
/// rows, separated by light dividers.
class ReadinessCheckCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final List<Widget> rows;

  const ReadinessCheckCard({
    super.key,
    required this.icon,
    required this.title,
    required this.rows,
    this.color = _accent,
  });

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      children.add(rows[i]);
      if (i != rows.length - 1) {
        children.add(Divider(height: 22, color: Theme.of(context).dividerColor));
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15.5)),
                ),
              ],
            ),
            Divider(height: 22, color: Theme.of(context).dividerColor),
            ...children,
          ],
        ),
      ),
    );
  }
}
