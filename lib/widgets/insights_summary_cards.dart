import 'package:flutter/material.dart';

import '../models/insights_data.dart';
import '../theme/app_theme.dart';

/// The four summary cards: Avg Heart Rate, Stress Indicator, Dominant Emotion,
/// Total Sessions. Driven entirely by [InsightsData].
class InsightsSummaryCards extends StatelessWidget {
  final InsightsData data;
  const InsightsSummaryCards({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _Card(
            icon: Icons.favorite,
            color: MedsColors.pink,
            label: 'Avg. Heart Rate',
            value: data.avgBpm > 0 ? '${data.avgBpm}' : '--',
            unit: 'BPM',
            delta: data.avgBpm > 0 ? _Delta(data.bpmDeltaPct) : null,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _Card(
            icon: Icons.speed,
            color: MedsColors.amber,
            label: 'Stress Level',
            value: data.validSessions > 0
                ? data.stressIndicator.toStringAsFixed(1)
                : '--',
            unit: '/ 5',
            delta: data.validSessions > 0 ? _Delta(data.stressDeltaPct) : null,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _Card(
            icon: Icons.mood,
            color: MedsColors.purple,
            label: 'Dominant Emotion',
            value: data.dominantEmotion,
            small: true,
            sub: data.validSessions > 0
                ? '${data.dominantPercent}% of valid'
                : '—',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _Card(
            icon: Icons.assignment,
            color: MedsColors.blue,
            label: 'Total Sessions',
            value: '${data.validSessions}',
            sub: 'valid',
          ),
        ),
      ],
    );
  }
}

/// A signed percentage comparison. For HR + stress, a decrease is an
/// improvement (green ↓); an increase is a caution (amber ↑).
class _Delta {
  final double pct;
  const _Delta(this.pct);
}

class _Card extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String? unit;
  final String? sub;
  final _Delta? delta;
  final bool small;

  const _Card({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.unit,
    this.sub,
    this.delta,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
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
            width: 30,
            height: 30,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, color: color, size: 16),
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
                  color: Theme.of(context).colorScheme.onSurface),
              children: [
                if (unit != null)
                  TextSpan(
                      text: ' $unit',
                      style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.normal,
                          color: MedsColors.muted)),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 3),
          if (delta != null)
            _deltaLabel(delta!)
          else if (sub != null)
            Text(sub!,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 9.5, color: MedsColors.muted)),
        ],
      ),
    );
  }

  Widget _deltaLabel(_Delta d) {
    final down = d.pct < 0;
    final flat = d.pct == 0;
    final color = flat
        ? MedsColors.muted
        : (down ? MedsColors.greenDark : MedsColors.amber);
    final icon = flat
        ? Icons.remove
        : (down ? Icons.arrow_downward : Icons.arrow_upward);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 2),
        Flexible(
          child: Text('${d.pct.abs().round()}% vs last',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 9.5, color: color)),
        ),
      ],
    );
  }
}
