import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// A pill-style segmented filter tab used across the admin screens — purple
/// when selected, outlined when not.
class AdminTabChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const AdminTabChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return Material(
      color: selected ? MedsColors.purple : surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: selected
                ? null
                : Border.all(color: MedsColors.muted.withValues(alpha: 0.25)),
          ),
          child: Text(label,
              style: TextStyle(
                  color: selected ? Colors.white : MedsColors.lightText,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
        ),
      ),
    );
  }
}
