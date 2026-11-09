import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'ui_kit.dart';

const Color _accent = Color(0xFF6A5AE0);

/// Empty / insufficient-data states for the Insights screen.
class InsightsEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Color color;

  /// When provided, shows a "Start New Session" button.
  final VoidCallback? onStart;

  /// When provided (and [onStart] is null), shows a "Try Again" button.
  final VoidCallback? onRetry;

  const InsightsEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.insights_outlined,
    this.color = MedsColors.purple,
    this.onStart,
    this.onRetry,
  });

  /// No completed sessions at all.
  factory InsightsEmptyState.noSessions(VoidCallback onStart) =>
      InsightsEmptyState(
        icon: Icons.insights_outlined,
        title: 'No insights available yet.',
        message: 'Complete several monitoring sessions to begin viewing your '
            'emotional and heart-rate trends.',
        color: MedsColors.purple,
        onStart: onStart,
      );

  /// Has sessions, but none valid in the selected period.
  factory InsightsEmptyState.insufficient(VoidCallback onStart) =>
      InsightsEmptyState(
        icon: Icons.hourglass_empty,
        title: 'Not enough valid data for this period.',
        message: 'Complete more sessions with a clear face and a connected '
            'heart-rate sensor to see insights here.',
        color: MedsColors.blue,
        onStart: onStart,
      );

  factory InsightsEmptyState.error(VoidCallback onRetry) => InsightsEmptyState(
        icon: Icons.cloud_off,
        title: 'Insights could not be loaded.',
        message: 'Please check your connection and try again.',
        color: MedsColors.red,
        onRetry: onRetry,
      );

  @override
  Widget build(BuildContext context) {
    Widget? action;
    if (onStart != null) {
      action = FilledButton.icon(
        onPressed: onStart,
        style: FilledButton.styleFrom(backgroundColor: _accent),
        icon: const Icon(Icons.play_arrow),
        label: const Text('Start New Session'),
      );
    } else if (onRetry != null) {
      action = FilledButton.icon(
        onPressed: onRetry,
        style: FilledButton.styleFrom(backgroundColor: _accent),
        icon: const Icon(Icons.refresh),
        label: const Text('Try Again'),
      );
    }
    return EmptyState(
      icon: icon,
      title: title,
      message: message,
      color: color,
      action: action,
    );
  }
}
