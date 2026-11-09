import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A rounded, soft-shadowed surface card used throughout MEDS. Replaces the
/// old flat bordered containers for a friendlier, more elevated look.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final VoidCallback? onTap;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final decoration = BoxDecoration(
      color: color ?? Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      border: dark ? Border.all(color: Theme.of(context).dividerColor) : null,
      boxShadow: softShadow(context),
    );

    if (onTap == null) {
      return Container(
        width: double.infinity,
        padding: padding,
        decoration: decoration,
        child: child,
      );
    }

    // Keep the shadow on the outer box, clip the ripple to the rounded shape.
    return DecoratedBox(
      decoration: decoration,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// A friendly, colourful section heading: a tinted icon chip plus a title.
/// Replaces the old all-caps grey labels for clearer visual hierarchy.
class SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final Widget? trailing;

  const SectionHeader({
    super.key,
    required this.title,
    required this.icon,
    this.color = medsGreen,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 2),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15)),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// A centred, friendly empty / placeholder state with a tinted icon.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Color color;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.color = medsGreen,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 46, color: color),
            ),
            const SizedBox(height: 18),
            Text(title,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(message!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: MedsColors.muted, fontSize: 14, height: 1.4)),
            ],
            if (action != null) ...[
              const SizedBox(height: 18),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// A small rounded status / category pill.
class Pill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;

  const Pill({super.key, required this.text, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(text,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.bold, fontSize: 11)),
        ],
      ),
    );
  }
}
