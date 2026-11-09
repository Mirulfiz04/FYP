import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'ui_kit.dart';

const Color _hr = MedsColors.pink;

/// Heart-rate card: current BPM (or a status when invalid), the personal normal
/// range, and a small real-time waveform.
class HeartRateCard extends StatelessWidget {
  final int? bpm; // null when there's no valid reading
  final String statusText; // shown when bpm is null
  final String rangeLabel; // e.g. "60–100 BPM"
  final List<int> history;

  const HeartRateCard({
    super.key,
    required this.bpm,
    required this.statusText,
    required this.rangeLabel,
    required this.history,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                    color: _hr.withValues(alpha: 0.15), shape: BoxShape.circle),
                child: const Icon(Icons.favorite, color: _hr, size: 24),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Heart Rate',
                      style: TextStyle(color: MedsColors.muted, fontSize: 12)),
                  const SizedBox(height: 2),
                  bpm != null
                      ? Text.rich(TextSpan(
                          text: '$bpm',
                          style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color: _hr),
                          children: const [
                            TextSpan(
                                text: ' BPM',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.normal,
                                    color: MedsColors.muted)),
                          ],
                        ))
                      : Text(statusText,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: MedsColors.muted)),
                ],
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 70,
                  child: history.length < 2
                      ? const Center(
                          child: Text('—',
                              style: TextStyle(color: MedsColors.muted)))
                      : LineChart(_waveform()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text.rich(TextSpan(
            text: 'Normal Range: ',
            style: const TextStyle(color: MedsColors.muted, fontSize: 12.5),
            children: [
              TextSpan(
                  text: rangeLabel,
                  style: const TextStyle(
                      color: _hr, fontWeight: FontWeight.w600)),
            ],
          )),
        ],
      ),
    );
  }

  LineChartData _waveform() {
    final spots = [
      for (var i = 0; i < history.length; i++)
        FlSpot(i.toDouble(), history[i].toDouble().clamp(40, 120)),
    ];
    return LineChartData(
      minY: 40,
      maxY: 120,
      minX: 0,
      maxX: (history.length - 1).toDouble(),
      gridData: const FlGridData(show: false),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 20,
            reservedSize: 26,
            getTitlesWidget: (v, _) => Text('${v.toInt()}',
                style: const TextStyle(color: MedsColors.muted, fontSize: 9)),
          ),
        ),
      ),
      lineTouchData: const LineTouchData(enabled: false),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: _hr,
          barWidth: 2.5,
          dotData: const FlDotData(show: false),
          belowBarData:
              BarAreaData(show: true, color: _hr.withValues(alpha: 0.12)),
        ),
      ],
    );
  }
}
