import 'package:flutter/material.dart';

/// A titled list of bullet points (e.g. "Positives", "Concerns",
/// "Recommendations") used by the admin AI trend and report screens. Renders
/// nothing when [items] is empty.
class InsightBulletList extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<String> items;

  const InsightBulletList({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(title,
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 13)),
          ],
        ),
        const SizedBox(height: 6),
        ...items.map((t) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 5, right: 8),
                    child: CircleAvatar(radius: 3, backgroundColor: color),
                  ),
                  Expanded(
                    child: Text(t,
                        style: const TextStyle(fontSize: 13, height: 1.35)),
                  ),
                ],
              ),
            )),
      ],
    );
  }
}
