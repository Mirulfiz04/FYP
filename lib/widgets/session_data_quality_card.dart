import 'package:flutter/material.dart';

import '../models/session_analytics.dart';
import '../theme/app_theme.dart';
import 'ui_kit.dart';

const Color _accent = Color(0xFF6A5AE0);

Color _reliabilityColor(String r) => switch (r) {
      'Good' => MedsColors.greenDark,
      'Fair' => MedsColors.amber,
      _ => MedsColors.red,
    };

/// Compact data-quality / reliability summary for the session.
class SessionDataQualityCard extends StatelessWidget {
  final SessionAnalytics analytics;
  const SessionDataQualityCard({super.key, required this.analytics});

  @override
  Widget build(BuildContext context) {
    final a = analytics;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.fact_check_outlined, color: _accent, size: 18),
              SizedBox(width: 8),
              Text('Data Quality',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 12),
          _row('Total readings', '${a.totalReadings}'),
          _row('Valid HR readings', '${a.validHrCount}'),
          _row('Invalid readings', '${a.invalidReadings}'),
          _row('Avg face confidence', '${a.avgConfidence}%'),
          _row('Sensor quality', a.sensorQuality),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Session reliability',
                      style: TextStyle(color: MedsColors.muted, fontSize: 13)),
                ),
                Pill(text: a.reliability, color: _reliabilityColor(a.reliability)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(color: MedsColors.muted, fontSize: 13)),
          ),
          Text(value,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }
}
