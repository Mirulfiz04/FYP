import 'package:flutter/material.dart';

import '../models/session_analytics.dart';
import '../theme/app_theme.dart';

/// The four headline metric cards: Dominant Emotion, Avg HR, Peak HR, Stress.
class SessionMetricCards extends StatelessWidget {
  final SessionAnalytics analytics;
  const SessionMetricCards({super.key, required this.analytics});

  @override
  Widget build(BuildContext context) {
    final a = analytics;
    final stressColor = MedsColors.stress(a.stressIndicator);
    return Row(
      children: [
        Expanded(
          child: _card(
            context,
            icon: Icons.mood,
            color: MedsColors.purple,
            label: 'Dominant Emotion',
            value: a.hasReadings ? a.dominantEmotion : '—',
            sub: a.hasReadings
                ? '${a.dominantPercent}% · ${a.dominantCount} readings'
                : 'No readings',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _card(
            context,
            icon: Icons.monitor_heart,
            color: MedsColors.blue,
            label: 'Avg Heart Rate',
            value: a.avgBpm != null ? '${a.avgBpm}' : '--',
            unit: a.avgBpm != null ? 'BPM' : null,
            sub: a.avgBpm == null ? 'No valid HR data' : null,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _card(
            context,
            icon: Icons.favorite,
            color: MedsColors.red,
            label: 'Peak Heart Rate',
            value: a.maxBpm != null ? '${a.maxBpm}' : '--',
            unit: a.maxBpm != null ? 'BPM' : null,
            sub: a.maxBpm == null ? 'No valid HR data' : null,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _card(
            context,
            icon: Icons.eco,
            color: stressColor,
            label: 'Stress Level',
            value: a.stressIndicator,
            valueColor: stressColor,
            small: true,
            sub: 'Wellness indicator',
          ),
        ),
      ],
    );
  }

  Widget _card(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String label,
    required String value,
    String? unit,
    String? sub,
    Color? valueColor,
    bool small = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: softShadow(context),
      ),
      child: Column(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 17),
          ),
          const SizedBox(height: 7),
          SizedBox(
            height: 26,
            child: Center(
              child: Text(label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 10.5, height: 1.05, color: MedsColors.muted)),
            ),
          ),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              text: value,
              style: TextStyle(
                  fontSize: small ? 14 : 18,
                  fontWeight: FontWeight.bold,
                  color:
                      valueColor ?? Theme.of(context).colorScheme.onSurface),
              children: [
                if (unit != null)
                  TextSpan(
                      text: ' $unit',
                      style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.normal,
                          color: MedsColors.muted)),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          if (sub != null)
            Text(sub,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 9, color: MedsColors.muted)),
        ],
      ),
    );
  }
}
