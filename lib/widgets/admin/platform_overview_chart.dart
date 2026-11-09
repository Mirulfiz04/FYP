import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../models/admin_dashboard_models.dart';
import '../../theme/app_theme.dart';
import '../ui_kit.dart';

/// "Platform Overview" card: a line chart of monitoring sessions over the
/// selected period, with a Today / This Week / This Month / Custom selector and
/// touch tooltips. Shows an empty state when there is no session activity.
class PlatformOverviewChart extends StatelessWidget {
  final List<SessionTrendPoint> points;
  final DashboardPeriod period;
  final ValueChanged<DashboardPeriod> onPeriodChanged;

  const PlatformOverviewChart({
    super.key,
    required this.points,
    required this.period,
    required this.onPeriodChanged,
  });

  bool get _hasData => points.any((p) => p.sessions > 0);

  @override
  Widget build(BuildContext context) {
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
                child: const Icon(Icons.show_chart,
                    size: 16, color: MedsColors.purple),
              ),
              const SizedBox(width: 9),
              const Expanded(
                child: Text('Platform Overview',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5)),
              ),
              _periodSelector(context),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 16,
                height: 4,
                decoration: BoxDecoration(
                  color: MedsColors.blue,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
              const Text('Sessions',
                  style: TextStyle(color: MedsColors.muted, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 190,
            child: !_hasData
                ? const _EmptyChart()
                : Padding(
                    padding: const EdgeInsets.only(right: 6, top: 4),
                    child: LineChart(_chartData()),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _periodSelector(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      decoration: BoxDecoration(
        color: MedsColors.purple.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<DashboardPeriod>(
          value: period,
          isDense: true,
          borderRadius: BorderRadius.circular(14),
          icon: const Icon(Icons.keyboard_arrow_down,
              size: 18, color: MedsColors.purple),
          style: const TextStyle(
              color: MedsColors.purple,
              fontSize: 12.5,
              fontWeight: FontWeight.w600),
          onChanged: (p) {
            if (p != null) onPeriodChanged(p);
          },
          selectedItemBuilder: (_) => DashboardPeriod.values
              .map((p) => Align(
                    alignment: Alignment.centerLeft,
                    child: Text(p.label,
                        style: const TextStyle(
                            color: MedsColors.purple,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600)),
                  ))
              .toList(),
          items: DashboardPeriod.values
              .map((p) =>
                  DropdownMenuItem(value: p, child: Text(p.label)))
              .toList(),
        ),
      ),
    );
  }

  LineChartData _chartData() {
    final spots = <FlSpot>[
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].sessions.toDouble()),
    ];
    final maxSessions =
        points.map((p) => p.sessions).fold<int>(0, (a, b) => a > b ? a : b);
    final maxY = (maxSessions <= 0 ? 4 : (maxSessions * 1.25).ceil()).toDouble();
    final yInterval = (maxY / 4).clamp(1, double.infinity).toDouble();

    const axisStyle = TextStyle(color: MedsColors.muted, fontSize: 10.5);

    return LineChartData(
      minX: 0,
      maxX: (points.length - 1).clamp(0, double.infinity).toDouble(),
      minY: 0,
      maxY: maxY,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: yInterval,
        getDrawingHorizontalLine: (_) => FlLine(
          color: MedsColors.muted.withValues(alpha: 0.15),
          strokeWidth: 1,
        ),
      ),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: yInterval,
            reservedSize: 26,
            getTitlesWidget: (v, _) =>
                Text('${v.toInt()}', style: axisStyle),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 1,
            reservedSize: 24,
            getTitlesWidget: (v, _) {
              final i = v.round();
              if (i < 0 || i >= points.length) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(points[i].label, style: axisStyle),
              );
            },
          ),
        ),
      ),
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => MedsColors.lightText,
          tooltipRoundedRadius: 10,
          getTooltipItems: (touched) => touched.map((s) {
            final i = s.x.round();
            final label =
                (i >= 0 && i < points.length) ? points[i].label : '';
            return LineTooltipItem(
              '${s.y.toInt()} sessions\n',
              const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12.5),
              children: [
                TextSpan(
                  text: label,
                  style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w500,
                      fontSize: 11),
                ),
              ],
            );
          }).toList(),
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          preventCurveOverShooting: true,
          color: MedsColors.blue,
          barWidth: 3,
          dotData: FlDotData(
            show: true,
            getDotPainter: (s, p, b, i) => FlDotCirclePainter(
              radius: 3.5,
              color: Colors.white,
              strokeWidth: 2.5,
              strokeColor: MedsColors.blue,
            ),
          ),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                MedsColors.blue.withValues(alpha: 0.22),
                MedsColors.blue.withValues(alpha: 0.0),
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
          Icon(Icons.bar_chart_outlined,
              size: 38, color: MedsColors.muted.withValues(alpha: 0.6)),
          const SizedBox(height: 10),
          const Text('No session activity for this period',
              style: TextStyle(color: MedsColors.muted, fontSize: 13)),
        ],
      ),
    );
  }
}
