import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../models/admin_session_detail.dart';
import '../../theme/app_theme.dart';
import '../ui_kit.dart';

String _mmss(num seconds) {
  final s = seconds.round();
  final m = (s ~/ 60).toString().padLeft(2, '0');
  final sec = (s % 60).toString().padLeft(2, '0');
  return '$m:$sec';
}

/// "Heart Rate Trend" card: a purple BPM line over the session timeline with a
/// soft area gradient, a 40–120 scale and mm:ss time labels.
class HrTrendChart extends StatelessWidget {
  final List<HrPoint> points;
  final int avgBpm;

  const HrTrendChart({super.key, required this.points, required this.avgBpm});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Heart Rate Trend',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5)),
              ),
              if (points.isNotEmpty)
                Text.rich(TextSpan(children: [
                  const TextSpan(
                      text: 'Average ',
                      style: TextStyle(color: MedsColors.muted, fontSize: 12.5)),
                  TextSpan(
                      text: '$avgBpm BPM',
                      style: const TextStyle(
                          color: MedsColors.purple,
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5)),
                ])),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                      color: MedsColors.purple, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              const Text('BPM',
                  style: TextStyle(color: MedsColors.muted, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 180,
            child: points.length < 2
                ? const _EmptyChart()
                : Padding(
                    padding: const EdgeInsets.only(right: 6, top: 4),
                    child: LineChart(_data()),
                  ),
          ),
        ],
      ),
    );
  }

  LineChartData _data() {
    final maxX = points.last.seconds <= 0 ? 1.0 : points.last.seconds;
    final spots = [
      for (final p in points) FlSpot(p.seconds, p.bpm.toDouble().clamp(40, 120)),
    ];
    const axis = TextStyle(color: MedsColors.muted, fontSize: 10);

    return LineChartData(
      minX: 0,
      maxX: maxX,
      minY: 40,
      maxY: 120,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: 20,
        getDrawingHorizontalLine: (_) => FlLine(
            color: MedsColors.muted.withValues(alpha: 0.15), strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 20,
            reservedSize: 28,
            getTitlesWidget: (v, _) => Text('${v.toInt()}', style: axis),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: maxX / 5,
            reservedSize: 22,
            getTitlesWidget: (v, meta) {
              if (v <= 0 && meta.min != v) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_mmss(v), style: axis),
              );
            },
          ),
        ),
      ),
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => MedsColors.lightText,
          tooltipRoundedRadius: 10,
          getTooltipItems: (spots) => spots
              .map((s) => LineTooltipItem(
                    '${s.y.round()} BPM\n${_mmss(s.x)}',
                    const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12),
                  ))
              .toList(),
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          preventCurveOverShooting: true,
          color: MedsColors.purple,
          barWidth: 2.4,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                MedsColors.purple.withValues(alpha: 0.22),
                MedsColors.purple.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyChart extends StatelessWidget {
  const _EmptyChart();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.monitor_heart_outlined,
              size: 36, color: MedsColors.muted.withValues(alpha: 0.6)),
          const SizedBox(height: 10),
          const Text('No heart-rate data for this session',
              style: TextStyle(color: MedsColors.muted, fontSize: 13)),
        ],
      ),
    );
  }
}
