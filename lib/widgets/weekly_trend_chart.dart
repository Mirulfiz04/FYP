import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/insights_data.dart';

const Color _hrColor = Color(0xFFFF6B8A);
const Color _stressColor = Color(0xFF7CE0A0);

/// Purple gradient "Weekly Trends" card: heart-rate + stress lines on a dual
/// axis, with a Daily/Weekly/Monthly view dropdown and touch tooltips.
class WeeklyTrendChart extends StatelessWidget {
  final List<TrendPoint> points;
  final TrendGranularity granularity;
  final ValueChanged<TrendGranularity> onGranularityChanged;

  const WeeklyTrendChart({
    super.key,
    required this.points,
    required this.granularity,
    required this.onGranularityChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 14, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7A6CF0), Color(0xFF5E4FD0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6A5AE0).withValues(alpha: 0.32),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Weekly Trends',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold)),
              _granularityDropdown(),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _legend(_hrColor, 'Heart Rate (BPM)'),
              const SizedBox(width: 18),
              _legend(_stressColor, 'Stress Level (1-5)'),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 190,
            child: points.isEmpty
                ? const Center(
                    child: Text('Not enough data for this period.',
                        style: TextStyle(color: Colors.white70, fontSize: 13)))
                : LineChart(_chartData()),
          ),
        ],
      ),
    );
  }

  Widget _granularityDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<TrendGranularity>(
          value: granularity,
          isDense: true,
          dropdownColor: const Color(0xFF5E4FD0),
          iconEnabledColor: Colors.white,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          onChanged: (g) {
            if (g != null) onGranularityChanged(g);
          },
          items: const [
            DropdownMenuItem(
                value: TrendGranularity.daily, child: Text('View: Daily')),
            DropdownMenuItem(
                value: TrendGranularity.weekly, child: Text('View: Weekly')),
            DropdownMenuItem(
                value: TrendGranularity.monthly, child: Text('View: Monthly')),
          ],
        ),
      ),
    );
  }

  Widget _legend(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
      ],
    );
  }

  LineChartData _chartData() {
    final hr = <FlSpot>[];
    final stress = <FlSpot>[];
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      if (p.bpm != null) {
        hr.add(FlSpot(i.toDouble(), p.bpm!.clamp(40, 100)));
      }
      if (p.stress != null) {
        stress.add(FlSpot(i.toDouble(), 40 + (p.stress! - 1) / 4 * 60));
      }
    }
    const white = TextStyle(color: Colors.white70, fontSize: 10);

    return LineChartData(
      minX: 0,
      maxX: (points.length - 1).clamp(0, double.infinity).toDouble(),
      minY: 40,
      maxY: 100,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: 20,
        getDrawingHorizontalLine: (_) =>
            FlLine(color: Colors.white.withValues(alpha: 0.15), strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 20,
            reservedSize: 28,
            getTitlesWidget: (v, _) => Text('${v.toInt()}', style: white),
          ),
        ),
        rightTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 15,
            reservedSize: 18,
            getTitlesWidget: (v, _) {
              if (v < 40 || v > 100) return const SizedBox.shrink();
              return Text('${((v - 40) / 60 * 4 + 1).round()}', style: white);
            },
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 1,
            reservedSize: 22,
            getTitlesWidget: (v, _) {
              final i = v.round();
              if (i < 0 || i >= points.length) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(points[i].label, style: white),
              );
            },
          ),
        ),
      ),
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => Colors.white,
          getTooltipItems: (spots) => spots.map((s) {
            final isHr = s.barIndex == 0;
            final value = isHr
                ? '${s.y.round()} BPM'
                : ((s.y - 40) / 60 * 4 + 1).toStringAsFixed(1);
            return LineTooltipItem(
              isHr ? 'HR $value' : 'Stress $value',
              TextStyle(
                  color: isHr ? const Color(0xFFD81B60) : const Color(0xFF1B8A53),
                  fontWeight: FontWeight.w600,
                  fontSize: 12),
            );
          }).toList(),
        ),
      ),
      lineBarsData: [
        _line(hr, _hrColor),
        _line(stress, _stressColor),
      ],
    );
  }

  LineChartBarData _line(List<FlSpot> spots, Color color) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      color: color,
      barWidth: 3,
      dotData: FlDotData(
        show: true,
        getDotPainter: (s, p, b, i) =>
            FlDotCirclePainter(radius: 3.5, color: color, strokeWidth: 0),
      ),
      belowBarData: BarAreaData(
        show: true,
        color: color.withValues(alpha: 0.12),
      ),
    );
  }
}
