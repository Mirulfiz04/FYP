import 'package:flutter/material.dart';

import '../../models/admin_insights_model.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui_kit.dart';

/// On-brand detail screen for "Session Performance" — expands each headline
/// metric (completion rate, AI summaries reviewed, average detection time) with
/// a progress bar, a vs-previous-period change and a plain-English explanation.
class AdminPerformanceDetailScreen extends StatelessWidget {
  final SessionPerformance performance;
  final String comparison;

  const AdminPerformanceDetailScreen({
    super.key,
    required this.performance,
    required this.comparison,
  });

  @override
  Widget build(BuildContext context) {
    final p = performance;
    final detection = p.avgDetectionSeconds;
    return Scaffold(
      appBar: AppBar(title: const Text('Session Performance')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'How reliably monitoring sessions run across the platform for the '
            'selected period.',
            style: TextStyle(color: MedsColors.muted, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 16),
          _MetricDetailCard(
            icon: Icons.check_circle_outline,
            color: MedsColors.greenDark,
            title: 'Completion Rate',
            valueText: '${p.completionRate.round()}%',
            fraction: p.completionRate / 100,
            delta: _delta(p.completionDelta, unit: '%'),
            deltaGood: p.completionDelta >= 0,
            comparison: comparison,
            description:
                'Share of monitoring sessions that finished normally rather '
                'than being cancelled or abandoned.',
          ),
          const SizedBox(height: 14),
          _MetricDetailCard(
            icon: Icons.description_outlined,
            color: MedsColors.blue,
            title: 'AI Summaries Reviewed',
            valueText: '${p.aiReviewedRate.round()}%',
            fraction: p.aiReviewedRate / 100,
            delta: _delta(p.aiReviewedDelta, unit: '%'),
            deltaGood: p.aiReviewedDelta >= 0,
            comparison: comparison,
            description:
                'Share of completed sessions that have a generated AI wellness '
                'summary available for review.',
          ),
          const SizedBox(height: 14),
          _MetricDetailCard(
            icon: Icons.timer_outlined,
            color: MedsColors.purple,
            title: 'Avg Detection Time',
            valueText: detection == null ? '—' : '${detection}s',
            fraction:
                detection == null ? 0 : (1 - (detection / 5)).clamp(0.0, 1.0),
            delta: p.detectionDelta == null
                ? null
                : _delta(p.detectionDelta!, unit: 's'),
            deltaGood: (p.detectionDelta ?? 0) <= 0, // faster is better
            comparison: comparison,
            description:
                'Average time between emotion and heart-rate readings during a '
                'session. Lower is faster.',
          ),
          const SizedBox(height: 16),
          AppCard(
            color: MedsColors.purple.withValues(alpha: 0.06),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: MedsColors.purple, size: 18),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'These are operational indicators for administrators — not '
                    'a clinical or medical measure.',
                    style: TextStyle(fontSize: 12, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String? _delta(double value, {required String unit}) {
    if (value == 0) return null;
    final arrow = value > 0 ? '↑' : '↓';
    final mag = unit == 's'
        ? value.abs().toStringAsFixed(1)
        : value.abs().toStringAsFixed(0);
    return '$arrow $mag$unit';
  }
}

class _MetricDetailCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String valueText;
  final double fraction;
  final String? delta;
  final bool deltaGood;
  final String comparison;
  final String description;

  const _MetricDetailCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.valueText,
    required this.fraction,
    required this.delta,
    required this.deltaGood,
    required this.comparison,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final deltaColor = deltaGood ? MedsColors.greenDark : MedsColors.red;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15.5)),
              ),
              const SizedBox(width: 8),
              Text(valueText,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 20)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: LinearProgressIndicator(
              value: fraction.clamp(0.0, 1.0),
              minHeight: 9,
              backgroundColor: color.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (delta != null) ...[
                Text(delta!,
                    style: TextStyle(
                        color: deltaColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12)),
                const SizedBox(width: 6),
                Text(comparison,
                    style:
                        const TextStyle(color: MedsColors.muted, fontSize: 12)),
              ] else
                const Text('No change data for this period',
                    style: TextStyle(color: MedsColors.muted, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 10),
          Text(description,
              style: const TextStyle(
                  color: MedsColors.muted, fontSize: 12.5, height: 1.45)),
        ],
      ),
    );
  }
}
