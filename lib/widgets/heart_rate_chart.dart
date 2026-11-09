import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/session_analytics.dart';
import '../theme/app_theme.dart';
import 'ui_kit.dart';

const Color _accent = Color(0xFF6A5AE0);

/// Heart Rate Trend card: BPM over time from valid readings only, with an
/// average/max/min header and an empty state.
class HeartRateChart extends StatelessWidget {
  final SessionAnalytics analytics;
  const HeartRateChart({super.key, required this.analytics});

  @override
  Widget build(BuildContext context) {
    final pts = analytics.hrTrend;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.monitor_heart, color: _accent, size: 18),
              const SizedBox(width: 8),
              const Text('Heart Rate Trend',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 6),
          if (analytics.hasValidHr)
            Text.rich(TextSpan(
              style: const TextStyle(fontSize: 12, color: MedsColors.muted),
              children: [
                const TextSpan(text: 'Average '),
                TextSpan(
                    text: '${analytics.avgBpm} BPM',
                    style: const TextStyle(
                        color: _accent, fontWeight: FontWeight.w600)),
                const TextSpan(text: '  ·  Max '),
                TextSpan(
                    text: '${analytics.maxBpm} BPM',
                    style: const TextStyle(
                        color: MedsColors.red, fontWeight: FontWeight.w600)),
                const TextSpan(text: '  ·  Min '),
                TextSpan(
                    text: '${analytics.minBpm} BPM',
                    style: const TextStyle(
                        color: MedsColors.greenDark,
                        fontWeight: FontWeight.w600)),
              ],
            )),
          const SizedBox(height: 14),
          if (pts.length < 2)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 22),
              child: Center(
                child: Text('No valid heart-rate data for this session.',
                    style: TextStyle(color: MedsColors.muted, fontSize: 13)),
              ),
            )
          else
            _chart(pts),
        ],
      ),
    );
  }

  Widget _chart(List<HrPoint> pts) {
    final scrollable = pts.length > 40;
    final chart = SizedBox(
      height: 170,
      width: scrollable ? pts.length * 9.0 : null,
      child: LineChart(_data(pts)),
    );
    if (scrollable) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: chart,
      );
    }
    return chart;
  }

  LineChartData _data(List<HrPoint> pts) {
    final values = pts.map((p) => p.bpm).toList();
    final lo = values.reduce((a, b) => a < b ? a : b);
    final hi = values.reduce((a, b) => a > b ? a : b);
    final minY = ((lo - 10) ~/ 10 * 10).clamp(30, 200).toDouble();
    final maxY = (((hi + 10) / 10).ceil() * 10).clamp(60, 220).toDouble();
    final step = (pts.length / 5).ceil().clamp(1, pts.length);

    return LineChartData(
      minX: 0,
      maxX: (pts.length - 1).toDouble(),
      minY: minY,
      maxY: maxY,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: 20,
        getDrawingHorizontalLine: (_) =>
            FlLine(color: const Color(0x141B2333), strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipItems: (spots) => spots
              .map((s) => LineTooltipItem('${s.y.round()} BPM',
                  const TextStyle(
                      color: _accent,
                      fontWeight: FontWeight.w600,
                      fontSize: 12)))
              .toList(),
        ),
      ),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          axisNameWidget: const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text('BPM',
                style: TextStyle(color: MedsColors.muted, fontSize: 10)),
          ),
          axisNameSize: 16,
          sideTitles: SideTitles(
            showTitles: true,
            interval: 20,
            reservedSize: 30,
            getTitlesWidget: (v, _) => Text('${v.toInt()}',
                style: const TextStyle(color: MedsColors.muted, fontSize: 10)),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 1,
            reservedSize: 24,
            getTitlesWidget: (v, _) {
              final i = v.round();
              if (i < 0 || i >= pts.length) return const SizedBox.shrink();
              if (i != 0 && i != pts.length - 1 && i % step != 0) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(DateFormat('HH:mm:ss').format(pts[i].time.toLocal()),
                    style:
                        const TextStyle(color: MedsColors.muted, fontSize: 9)),
              );
            },
          ),
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: [
            for (var i = 0; i < pts.length; i++)
              FlSpot(i.toDouble(), pts[i].bpm.toDouble()),
          ],
          isCurved: true,
          color: _accent,
          barWidth: 2.5,
          dotData: const FlDotData(show: false),
          belowBarData:
              BarAreaData(show: true, color: _accent.withValues(alpha: 0.10)),
        ),
      ],
    );
  }
}
