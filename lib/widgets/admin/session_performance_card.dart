import 'package:flutter/material.dart';

import '../../models/admin_insights_model.dart';
import '../../theme/app_theme.dart';
import '../ui_kit.dart';

/// "Session Performance" card: completion rate, AI summaries reviewed and the
/// average detection time, each with a coloured progress bar and a vs-previous
/// delta. Null-safe — an unavailable metric renders as "—".
class SessionPerformanceCard extends StatelessWidget {
  final SessionPerformance performance;
  final String comparison;
  final VoidCallback onDetails;

  const SessionPerformanceCard({
    super.key,
    required this.performance,
    required this.comparison,
    required this.onDetails,
  });

  @override
  Widget build(BuildContext context) {
    final p = performance;
    final detection = p.avgDetectionSeconds;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: MedsColors.purple.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.bar_chart_rounded,
                    size: 16, color: MedsColors.purple),
              ),
              const SizedBox(width: 9),
              const Text('Session Performance',
                  style:
                      TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5)),
            ],
          ),
          const SizedBox(height: 16),
          _MetricRow(
            icon: Icons.check_circle_outline,
            color: MedsColors.greenDark,
            label: 'Completion Rate',
            valueText: '${p.completionRate.round()}%',
            fraction: p.completionRate / 100,
            delta: _deltaText(p.completionDelta, unit: '%'),
            deltaGood: p.completionDelta >= 0,
            comparison: comparison,
          ),
          const SizedBox(height: 16),
          _MetricRow(
            icon: Icons.description_outlined,
            color: MedsColors.blue,
            label: 'AI Summaries Reviewed',
            valueText: '${p.aiReviewedRate.round()}%',
            fraction: p.aiReviewedRate / 100,
            delta: _deltaText(p.aiReviewedDelta, unit: '%'),
            deltaGood: p.aiReviewedDelta >= 0,
            comparison: comparison,
          ),
          const SizedBox(height: 16),
          _MetricRow(
            icon: Icons.timer_outlined,
            color: MedsColors.purple,
            label: 'Avg Detection Time',
            valueText: detection == null ? '—' : '${detection}s',
            fraction:
                detection == null ? 0 : (1 - (detection / 5)).clamp(0.0, 1.0),
            delta: p.detectionDelta == null
                ? null
                : _deltaText(p.detectionDelta!, unit: 's'),
            // Faster (negative delta) is an improvement.
            deltaGood: (p.detectionDelta ?? 0) <= 0,
            comparison: comparison,
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 4),
          Center(
            child: TextButton(
              onPressed: onDetails,
              child: const Text('View Performance Details',
                  style: TextStyle(
                      color: MedsColors.purple,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5)),
            ),
          ),
        ],
      ),
    );
  }

  String? _deltaText(double value, {required String unit}) {
    if (value == 0) return null;
    final arrow = value > 0 ? '↑' : '↓';
    final mag = unit == 's'
        ? value.abs().toStringAsFixed(1)
        : value.abs().toStringAsFixed(0);
    return '$arrow $mag$unit';
  }
}

class _MetricRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String valueText;
  final double fraction;
  final String? delta;
  final bool deltaGood;
  final String comparison;

  const _MetricRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.valueText,
    required this.fraction,
    required this.delta,
    required this.deltaGood,
    required this.comparison,
  });

  @override
  Widget build(BuildContext context) {
    final deltaColor = deltaGood ? MedsColors.greenDark : MedsColors.red;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13.5)),
                  ),
                  const SizedBox(width: 8),
                  Text(valueText,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 15)),
                ],
              ),
              const SizedBox(height: 7),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: fraction.clamp(0.0, 1.0),
                  minHeight: 7,
                  backgroundColor: color.withValues(alpha: 0.12),
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
              if (delta != null) ...[
                const SizedBox(height: 5),
                Row(
                  children: [
                    Text(delta!,
                        style: TextStyle(
                            color: deltaColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 11)),
                    const SizedBox(width: 5),
                    Text(comparison,
                        style: const TextStyle(
                            color: MedsColors.muted, fontSize: 11)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
