import 'package:flutter/material.dart';

import '../models/session_readiness.dart';
import '../theme/app_theme.dart';

Color _levelColor(CheckLevel l) => switch (l) {
      CheckLevel.ok => MedsColors.greenDark,
      CheckLevel.warn => MedsColors.amber,
      CheckLevel.error => MedsColors.red,
      CheckLevel.checking => MedsColors.muted,
      CheckLevel.idle => MedsColors.muted,
    };

/// One check inside a readiness card: a leading icon, a label, the status text +
/// status indicator, and (when there's a problem) an inline message with an
/// optional action button. No SnackBars — messages live inline here.
class ReadinessStatusRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final CheckView view;
  final String? actionLabel;
  final VoidCallback? onAction;

  const ReadinessStatusRow({
    super.key,
    required this.icon,
    required this.label,
    required this.view,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final color = _levelColor(view.level);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: MedsColors.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500)),
            ),
            Text(view.text,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(width: 8),
            _indicator(color),
          ],
        ),
        if (view.message != null) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(view.message!,
                    style: const TextStyle(fontSize: 12, height: 1.35)),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      onPressed: onAction,
                      style: FilledButton.styleFrom(
                        backgroundColor: color,
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: Text(actionLabel!),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _indicator(Color color) {
    return switch (view.level) {
      CheckLevel.checking => const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2)),
      CheckLevel.ok => _badge(Icons.check, MedsColors.greenDark),
      CheckLevel.warn => Icon(Icons.warning_amber_rounded, color: color, size: 22),
      CheckLevel.error => _badge(Icons.priority_high, MedsColors.red),
      CheckLevel.idle =>
        const Icon(Icons.radio_button_unchecked, color: MedsColors.muted, size: 20),
    };
  }

  Widget _badge(IconData icon, Color color) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Icon(icon, color: Colors.white, size: 15),
    );
  }
}
