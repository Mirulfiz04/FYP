import 'package:flutter/material.dart';

import '../services/live_insight_rules.dart';
import '../theme/app_theme.dart';

const Color _accent = Color(0xFF6A5AE0);

/// Live Insights card — a short, locally-computed monitoring message (never a
/// per-update AI call), clearly framed as not a medical diagnosis.
class LiveInsightCard extends StatelessWidget {
  final String message;
  const LiveInsightCard({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _accent.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.auto_awesome, size: 17, color: _accent),
                    SizedBox(width: 6),
                    Text('Live Insights',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: _accent)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(message,
                    style: const TextStyle(fontSize: 13.5, height: 1.4)),
                const SizedBox(height: 8),
                Text(LiveInsightRules.disclaimer,
                    style: const TextStyle(
                        color: MedsColors.muted, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.psychology_alt, size: 40, color: _accent),
        ],
      ),
    );
  }
}
