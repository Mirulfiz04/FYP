import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../viewmodels/live_session_controller.dart';

/// Green/amber status banner with an animated indicator dot, reflecting the
/// current [LiveStatus].
class SessionStatusBanner extends StatelessWidget {
  final LiveStatus status;
  const SessionStatusBanner({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final (title, subtitle, color, icon) = switch (status) {
      LiveStatus.active => (
          'Session Active',
          'Live Monitoring in Progress',
          MedsColors.greenDark,
          Icons.monitor_heart_outlined
        ),
      LiveStatus.paused => (
          'Session Paused',
          'Recording is paused',
          MedsColors.amber,
          Icons.pause_circle_outline
        ),
      LiveStatus.sensorWarning => (
          'Sensor Warning',
          'Check the warning below',
          MedsColors.amber,
          Icons.warning_amber_rounded
        ),
      LiveStatus.ending => (
          'Ending Session',
          'Saving your data…',
          MedsColors.muted,
          Icons.hourglass_top
        ),
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          _PulsingDot(color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: color, fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(
                        color: MedsColors.muted, fontSize: 12.5)),
              ],
            ),
          ),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 20),
          ),
        ],
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 1))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: 0.5 * (1 - _c.value)),
              blurRadius: 8 * _c.value,
              spreadRadius: 4 * _c.value,
            ),
          ],
        ),
      ),
    );
  }
}
