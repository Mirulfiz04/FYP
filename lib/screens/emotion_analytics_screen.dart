import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/emotion_reading.dart';
import '../services/supabase_service.dart';

/// Per-user emotion + heart-rate analytics. Reused by the user (their own data)
/// and by an admin viewing any user.
class EmotionAnalyticsScreen extends StatefulWidget {
  final String userId;
  final String title;
  final String? subtitle;
  final String? avatarUrl;

  const EmotionAnalyticsScreen({
    super.key,
    required this.userId,
    required this.title,
    this.subtitle,
    this.avatarUrl,
  });

  @override
  State<EmotionAnalyticsScreen> createState() => _EmotionAnalyticsScreenState();
}

class _EmotionAnalyticsScreenState extends State<EmotionAnalyticsScreen> {
  final _svc = SupabaseService();
  List<EmotionReading> _readings = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _svc.fetchReadingsForUser(widget.userId);
      if (mounted) {
        setState(() {
          _readings = data;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _emotionColor(String e) => switch (e) {
        'Happy' => const Color(0xFF00DC64),
        'Sad' => const Color(0xFF5578C8),
        'Angry' => const Color(0xFFFF3232),
        'Fear' => const Color(0xFF9B30FF),
        'Surprise' => const Color(0xFF00FFFF),
        'Disgust' => const Color(0xFFFFA500),
        'Neutral' => const Color(0xFFB4B4B4),
        _ => Colors.grey,
      };

  Map<String, int> get _emotionCounts {
    final m = <String, int>{};
    for (final r in _readings) {
      m[r.emotion] = (m[r.emotion] ?? 0) + 1;
    }
    return m;
  }

  List<int> get _hrValues =>
      _readings.where((r) => r.hr > 0).map((r) => r.hr).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Emotion Analytics'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF00DC64)))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _header(),
                  const SizedBox(height: 20),
                  if (_readings.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Text(
                          'No readings yet.\nRun a detection session to see analytics.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey, fontSize: 15),
                        ),
                      ),
                    )
                  else ...[
                    _emotionSection(),
                    const SizedBox(height: 24),
                    _heartRateSection(),
                    const SizedBox(height: 24),
                    _recentSection(),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _header() {
    final hasAvatar =
        widget.avatarUrl != null && widget.avatarUrl!.isNotEmpty;
    return Row(
      children: [
        CircleAvatar(
          radius: 26,
          backgroundColor: const Color(0xFF00DC64).withValues(alpha: 0.15),
          backgroundImage: hasAvatar ? NetworkImage(widget.avatarUrl!) : null,
          child: !hasAvatar
              ? const Icon(Icons.person, color: Color(0xFF00DC64))
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              Text(widget.subtitle ?? '${_readings.length} readings',
                  style: const TextStyle(color: Colors.grey, fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }

  // ---- Emotions -----------------------------------------------------------

  Widget _emotionSection() {
    final counts = _emotionCounts;
    final total = counts.values.fold(0, (a, b) => a + b);
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final dominant = entries.first;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('EMOTIONS'),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Most frequent: ',
                  style: TextStyle(color: Colors.grey)),
              Text(dominant.key,
                  style: TextStyle(
                      color: _emotionColor(dominant.key),
                      fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 170,
            child: Row(
              children: [
                SizedBox(
                  width: 150,
                  child: PieChart(PieChartData(
                    centerSpaceRadius: 30,
                    sectionsSpace: 2,
                    sections: entries.map((e) {
                      final pct = e.value / total;
                      return PieChartSectionData(
                        value: e.value.toDouble(),
                        color: _emotionColor(e.key),
                        radius: 55,
                        title: pct >= 0.08
                            ? '${(pct * 100).toStringAsFixed(0)}%'
                            : '',
                        titleStyle: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.bold),
                      );
                    }).toList(),
                  )),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: entries.map((e) {
                      final pct =
                          (e.value / total * 100).toStringAsFixed(1);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            CircleAvatar(
                                radius: 5,
                                backgroundColor: _emotionColor(e.key)),
                            const SizedBox(width: 6),
                            Text(e.key,
                                style: TextStyle(
                                    color: _emotionColor(e.key),
                                    fontSize: 12)),
                            const Spacer(),
                            Text('${e.value}  ·  $pct%',
                                style: const TextStyle(
                                    color: Colors.grey, fontSize: 12)),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---- Heart rate ---------------------------------------------------------

  Widget _heartRateSection() {
    final hr = _hrValues;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('HEART RATE'),
          const SizedBox(height: 12),
          if (hr.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No heart-rate data — the ESP32 sensor was not connected '
                'during these readings.',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            )
          else ...[
            Row(
              children: [
                _hrStat('Average', '${_avg(hr)}'),
                _hrStat('Min', '${hr.reduce((a, b) => a < b ? a : b)}'),
                _hrStat('Max', '${hr.reduce((a, b) => a > b ? a : b)}'),
                _hrStat('Latest', '${hr.first}'),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(height: 140, child: _hrChart(hr)),
            const SizedBox(height: 4),
            const Center(
              child: Text('Beats per minute over time',
                  style: TextStyle(color: Colors.grey, fontSize: 11)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _hrChart(List<int> hrDesc) {
    // readings are newest-first; reverse to chronological and cap length.
    final chrono = hrDesc.reversed.toList();
    final data = chrono.length > 60
        ? chrono.sublist(chrono.length - 60)
        : chrono;
    final spots = <FlSpot>[
      for (var i = 0; i < data.length; i++) FlSpot(i.toDouble(), data[i].toDouble()),
    ];
    final minV = data.reduce((a, b) => a < b ? a : b);
    final maxV = data.reduce((a, b) => a > b ? a : b);

    return LineChart(LineChartData(
      minY: (minV - 5).toDouble(),
      maxY: (maxV + 5).toDouble(),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) =>
            FlLine(color: Theme.of(context).dividerColor, strokeWidth: 1),
      ),
      titlesData: FlTitlesData(
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 34,
            interval: ((maxV + 5) - (minV - 5)) / 2,
            getTitlesWidget: (value, meta) => Text(
              value.toInt().toString(),
              style: const TextStyle(color: Colors.grey, fontSize: 10),
            ),
          ),
        ),
      ),
      borderData: FlBorderData(show: false),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: const Color(0xFFFF4040),
          barWidth: 2,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            color: const Color(0xFFFF4040).withValues(alpha: 0.12),
          ),
        ),
      ],
    ));
  }

  Widget _hrStat(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFFF4040))),
          Text(label,
              style: const TextStyle(color: Colors.grey, fontSize: 11)),
        ],
      ),
    );
  }

  int _avg(List<int> v) =>
      (v.reduce((a, b) => a + b) / v.length).round();

  // ---- Recent readings ----------------------------------------------------

  Widget _recentSection() {
    final recent = _readings.take(30).toList();
    final fmt = DateFormat('dd MMM • HH:mm:ss');
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('RECENT READINGS'),
          const SizedBox(height: 4),
          ...recent.map((r) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    CircleAvatar(
                        radius: 5,
                        backgroundColor: _emotionColor(r.emotion)),
                    const SizedBox(width: 8),
                    Text(r.emotion,
                        style: TextStyle(
                            color: _emotionColor(r.emotion),
                            fontWeight: FontWeight.w600)),
                    const SizedBox(width: 6),
                    Text('${r.confidence.toStringAsFixed(0)}%',
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 12)),
                    const Spacer(),
                    if (r.hr > 0) ...[
                      const Icon(Icons.favorite,
                          size: 11, color: Color(0xFFFF4040)),
                      const SizedBox(width: 3),
                      Text('${r.hr}',
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 12)),
                      const SizedBox(width: 8),
                    ],
                    Text(fmt.format(r.createdAt.toLocal()),
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 11)),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  // ---- Helpers ------------------------------------------------------------

  Widget _label(String text) => Text(text,
      style: const TextStyle(
          color: Colors.grey,
          fontWeight: FontWeight.bold,
          fontSize: 12,
          letterSpacing: 1));

  Widget _card({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: child,
      );
}
