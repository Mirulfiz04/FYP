import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../models/admin_insights_model.dart';
import '../../theme/app_theme.dart';
import '../ui_kit.dart';

enum AdminChartType { line, bar }

const Color _stressColor = MedsColors.purple;
const Color _bpmColor = MedsColors.pink;

// BPM is plotted on a secondary 40..120 axis, mapped into the shared 0..100
// space so both series share one chart.
const double _bpmMin = 40;
const double _bpmMax = 120;

double _bpmToPlot(double bpm) =>
    ((bpm - _bpmMin) / (_bpmMax - _bpmMin) * 100).clamp(0, 100);
double _plotToBpm(double plot) => _bpmMin + plot / 100 * (_bpmMax - _bpmMin);

/// "Weekly Trend Overview" card: average stress level (purple) and average BPM
/// (pink) over the period, switchable between a line and a bar chart, with a
/// legend, light grid, day labels, markers and tap tooltips.
class AdminWeeklyTrendChart extends StatelessWidget {
  final List<TrendDatum> points;
  final AdminChartType chartType;
  final ValueChanged<AdminChartType> onChartTypeChanged;

  const AdminWeeklyTrendChart({
    super.key,
    required this.points,
    required this.chartType,
    required this.onChartTypeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Flexible(
                child: Text('Weekly Trend Overview',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5)),
              ),
              const SizedBox(width: 6),
              const Tooltip(
                message:
                    'Average stress level and heart rate per day for the '
                    'selected period.',
                child: Icon(Icons.info_outline,
                    size: 16, color: MedsColors.muted),
              ),
              const Spacer(),
              _typeDropdown(),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _legend(_stressColor, 'Stress Level (Avg)'),
              _legend(_bpmColor, 'Avg BPM'),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 210,
            child: points.isEmpty
                ? const _EmptyChart()
                : (chartType == AdminChartType.line
                    ? LineChart(_lineData())
                    : BarChart(_barData())),
          ),
        ],
      ),
    );
  }

  Widget _typeDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      decoration: BoxDecoration(
        color: MedsColors.purple.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<AdminChartType>(
          value: chartType,
          isDense: true,
          borderRadius: BorderRadius.circular(14),
          icon: const Icon(Icons.keyboard_arrow_down,
              size: 18, color: MedsColors.purple),
          style: const TextStyle(
              color: MedsColors.purple,
              fontSize: 12.5,
              fontWeight: FontWeight.w600),
          onChanged: (t) {
            if (t != null) onChartTypeChanged(t);
          },
          items: const [
            DropdownMenuItem(
                value: AdminChartType.line, child: Text('Line Chart')),
            DropdownMenuItem(
                value: AdminChartType.bar, child: Text('Bar Chart')),
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
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(color: MedsColors.muted, fontSize: 11.5)),
      ],
    );
  }

  // ---- Shared axis / grid -------------------------------------------------

  FlGridData get _grid => FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: 25,
        getDrawingHorizontalLine: (_) => FlLine(
            color: MedsColors.muted.withValues(alpha: 0.15), strokeWidth: 1),
      );

  FlTitlesData get _titles {
    const axisStyle = TextStyle(color: MedsColors.muted, fontSize: 10);
    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          interval: 25,
          reservedSize: 26,
          getTitlesWidget: (v, _) =>
              Text('${v.toInt()}', style: axisStyle.copyWith(color: _stressColor)),
        ),
      ),
      rightTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          interval: 25,
          reservedSize: 28,
          getTitlesWidget: (v, _) => Text('${_plotToBpm(v).round()}',
              style: axisStyle.copyWith(color: _bpmColor)),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          interval: 1,
          reservedSize: 40,
          getTitlesWidget: (v, _) {
            final i = v.round();
            if (i < 0 || i >= points.length) return const SizedBox.shrink();
            final p = points[i];
            return Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(p.dayLabel,
                      style: axisStyle.copyWith(height: 1.1)),
                  if (p.dateLabel.isNotEmpty)
                    Text(p.dateLabel,
                        style: axisStyle.copyWith(fontSize: 9, height: 1.1)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ---- Line chart ---------------------------------------------------------

  LineChartData _lineData() {
    final stressSpots = <FlSpot>[
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].stress.clamp(0, 100)),
    ];
    final bpmSpots = <FlSpot>[
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), _bpmToPlot(points[i].bpm)),
    ];

    return LineChartData(
      minX: 0,
      maxX: (points.length - 1).clamp(0, double.infinity).toDouble(),
      minY: 0,
      maxY: 100,
      gridData: _grid,
      borderData: FlBorderData(show: false),
      titlesData: _titles,
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => MedsColors.lightText,
          tooltipRoundedRadius: 10,
          getTooltipItems: (spots) => spots.map((s) {
            final isStress = s.barIndex == 0;
            final label = isStress
                ? 'Stress ${s.y.round()}'
                : 'BPM ${_plotToBpm(s.y).round()}';
            return LineTooltipItem(
              label,
              TextStyle(
                  color: isStress ? const Color(0xFFD0BCFF) : const Color(0xFFFFC2D6),
                  fontWeight: FontWeight.w600,
                  fontSize: 12),
            );
          }).toList(),
        ),
      ),
      lineBarsData: [
        _line(stressSpots, _stressColor, fill: true),
        _line(bpmSpots, _bpmColor),
      ],
    );
  }

  LineChartBarData _line(List<FlSpot> spots, Color color, {bool fill = false}) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      preventCurveOverShooting: true,
      color: color,
      barWidth: 3,
      dotData: FlDotData(
        show: true,
        getDotPainter: (s, p, b, i) => FlDotCirclePainter(
            radius: 3.5, color: Colors.white, strokeWidth: 2.5, strokeColor: color),
      ),
      belowBarData: BarAreaData(
        show: fill,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.20),
            color.withValues(alpha: 0.0),
          ],
        ),
      ),
    );
  }

  // ---- Bar chart ----------------------------------------------------------

  BarChartData _barData() {
    return BarChartData(
      maxY: 100,
      minY: 0,
      gridData: _grid,
      borderData: FlBorderData(show: false),
      titlesData: _titles,
      barTouchData: BarTouchData(
        touchTooltipData: BarTouchTooltipData(
          getTooltipColor: (_) => MedsColors.lightText,
          tooltipRoundedRadius: 10,
          getTooltipItem: (group, gi, rod, ri) {
            final isStress = ri == 0;
            final value =
                isStress ? rod.toY.round() : _plotToBpm(rod.toY).round();
            return BarTooltipItem(
              isStress ? 'Stress $value' : 'BPM $value',
              const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
            );
          },
        ),
      ),
      barGroups: [
        for (var i = 0; i < points.length; i++)
          BarChartGroupData(
            x: i,
            barsSpace: 3,
            barRods: [
              _rod(points[i].stress.clamp(0, 100), _stressColor),
              _rod(_bpmToPlot(points[i].bpm), _bpmColor),
            ],
          ),
      ],
    );
  }

  BarChartRodData _rod(double y, Color color) => BarChartRodData(
        toY: y,
        color: color,
        width: 7,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
      );
}

class _EmptyChart extends StatelessWidget {
  const _EmptyChart();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.show_chart,
              size: 38, color: MedsColors.muted.withValues(alpha: 0.6)),
          const SizedBox(height: 10),
          const Text('Not enough valid sessions to chart this period',
              textAlign: TextAlign.center,
              style: TextStyle(color: MedsColors.muted, fontSize: 13)),
        ],
      ),
    );
  }
}
