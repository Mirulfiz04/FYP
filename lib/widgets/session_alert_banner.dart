import 'package:flutter/material.dart';

import '../services/session_alert_controller.dart';
import '../theme/app_theme.dart';

Color _indicatorColor(IndicatorState s) => switch (s) {
      IndicatorState.ok => MedsColors.green,
      IndicatorState.warning => MedsColors.amber,
      IndicatorState.error => MedsColors.red,
      IndicatorState.unknown => MedsColors.muted,
    };

IconData _indicatorIcon(IndicatorState s) => switch (s) {
      IndicatorState.ok => Icons.check_circle,
      IndicatorState.warning => Icons.warning_amber_rounded,
      IndicatorState.error => Icons.error,
      IndicatorState.unknown => Icons.remove_circle_outline,
    };

/// A persistent warning banner for an ongoing sensor/camera problem during a
/// live session. Shows the matching action button (Retry / Open Settings).
class SessionAlertBanner extends StatelessWidget {
  final SessionAlert alert;
  final VoidCallback? onRetry;
  final VoidCallback? onOpenSettings;

  const SessionAlertBanner({
    super.key,
    required this.alert,
    this.onRetry,
    this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final isError = alert.hasRetry || alert.hasOpenSettings;
    final color = isError ? MedsColors.red : MedsColors.amber;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(isError ? Icons.error_outline : Icons.warning_amber_rounded,
                  color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(alert.message,
                    style: const TextStyle(fontSize: 13, height: 1.35)),
              ),
            ],
          ),
          if (alert.hasRetry || alert.hasOpenSettings) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: alert.hasRetry ? onRetry : onOpenSettings,
                style: FilledButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                icon: Icon(
                    alert.hasRetry ? Icons.refresh : Icons.camera_alt_outlined,
                    size: 18),
                label: Text(
                    alert.hasRetry ? 'Retry Connection' : 'Allow Camera'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The three subsystem status indicators (Camera / Heart-rate Sensor / AI).
class StatusIndicatorRow extends StatelessWidget {
  final IndicatorState camera;
  final IndicatorState sensor;
  final IndicatorState ai;

  const StatusIndicatorRow({
    super.key,
    required this.camera,
    required this.sensor,
    required this.ai,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _chip('Camera', Icons.camera_alt_outlined, camera)),
        const SizedBox(width: 8),
        Expanded(
            child: _chip('Sensor', Icons.favorite_outline, sensor)),
        const SizedBox(width: 8),
        Expanded(child: _chip('AI', Icons.auto_awesome, ai)),
      ],
    );
  }

  Widget _chip(String label, IconData icon, IndicatorState state) {
    final color = _indicatorColor(state);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: color,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 4),
          Icon(_indicatorIcon(state), size: 13, color: color),
        ],
      ),
    );
  }
}
