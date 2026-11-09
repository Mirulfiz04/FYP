import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/ai_trend_report.dart';
import '../../models/emotion_reading.dart';
import '../../services/admin_service.dart';
import '../../services/ai_service.dart';
import '../../widgets/insight_bullets.dart';
import '../../widgets/ui_kit.dart';

/// Admin "AI Trend Analysis Dashboard": buckets recent readings into weekly or
/// monthly periods, visualizes positivity per period, and generates an
/// AI-written trend report.
class AdminAiTrendsScreen extends StatefulWidget {
  const AdminAiTrendsScreen({super.key});

  @override
  State<AdminAiTrendsScreen> createState() => _AdminAiTrendsScreenState();
}

class _AdminAiTrendsScreenState extends State<AdminAiTrendsScreen> {
  static const _green = Color(0xFF00DC64);
  static const _amber = Color(0xFFFFA500);
  static const _red = Color(0xFFFF3232);
  static const _positive = {'Happy', 'Surprise'};

  final _admin = AdminService();
  final _ai = AiService();

  List<EmotionReading> _readings = [];
  bool _loading = true;
  bool _monthly = false; // false = weekly

  AiTrendReport? _report;
  bool _reportLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _admin.fetchRecentReadings(limit: 1000);
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

  // ---- Bucketing ----------------------------------------------------------

  DateTime _weekStart(DateTime d) {
    final date = DateTime(d.year, d.month, d.day);
    return date.subtract(Duration(days: date.weekday - 1)); // Monday
  }

  List<_Bucket> _buildBuckets() {
    final map = <DateTime, List<EmotionReading>>{};
    for (final r in _readings) {
      final d = r.createdAt.toLocal();
      final key = _monthly ? DateTime(d.year, d.month) : _weekStart(d);
      map.putIfAbsent(key, () => []).add(r);
    }
    final keys = map.keys.toList()..sort();
    final maxN = _monthly ? 6 : 8;
    final shown =
        keys.length > maxN ? keys.sublist(keys.length - maxN) : keys;
    return [
      for (final k in shown)
        _Bucket(
          label: _monthly
              ? DateFormat('MMM yyyy').format(k)
              : DateFormat('dd MMM').format(k),
          shortLabel: _monthly
              ? DateFormat('MMM').format(k)
              : DateFormat('dd/MM').format(k),
          readings: map[k]!,
        ),
    ];
  }

  String _buildSummary(List<_Bucket> buckets) {
    final buf = StringBuffer();
    buf.writeln('Granularity: ${_monthly ? 'monthly' : 'weekly'}');
    buf.writeln('Periods (oldest to newest):');
    for (final b in buckets) {
      buf.writeln('- ${b.label}: ${b.total} readings, '
          'dominant ${b.dominant}, positivity ${b.positivity}%, '
          'avg HR ${b.avgHr > 0 ? b.avgHr : 'n/a'}');
    }
    return buf.toString();
  }

  Color _barColor(int positivity) {
    if (positivity >= 60) return _green;
    if (positivity >= 40) return _amber;
    return _red;
  }

  // ---- Actions ------------------------------------------------------------

  Future<void> _generate(List<_Bucket> buckets) async {
    setState(() {
      _reportLoading = true;
      _error = null;
    });
    try {
      final report = await _ai.generateTrendAnalysis(
        dataSummary: _buildSummary(buckets),
        granularity: _monthly ? 'monthly' : 'weekly',
      );
      if (mounted) {
        setState(() {
          _report = report;
          _reportLoading = false;
        });
      }
    } on AiException catch (e) {
      if (mounted) {
        setState(() {
          _reportLoading = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _reportLoading = false;
          _error = 'Something went wrong generating the trend analysis.';
        });
      }
    }
  }

  // ---- UI -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final buckets = _loading ? <_Bucket>[] : _buildBuckets();
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Trend Analysis'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _green))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Weekly')),
                    ButtonSegment(value: true, label: Text('Monthly')),
                  ],
                  selected: {_monthly},
                  onSelectionChanged: (s) => setState(() {
                    _monthly = s.first;
                    _report = null; // periods changed — old report no longer fits
                    _error = null;
                  }),
                ),
                const SizedBox(height: 16),
                if (buckets.isEmpty)
                  _card(const Text(
                    'No readings yet to build trends from.',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ))
                else ...[
                  _chartCard(buckets),
                  const SizedBox(height: 16),
                  _reportSection(buckets),
                ],
              ],
            ),
    );
  }

  Widget _chartCard(List<_Bucket> buckets) {
    const barAreaHeight = 120.0;
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('POSITIVITY PER PERIOD',
              style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 1)),
          const SizedBox(height: 4),
          const Text('% of readings that were Happy or Surprise',
              style: TextStyle(color: Colors.grey, fontSize: 11)),
          const SizedBox(height: 16),
          SizedBox(
            height: barAreaHeight + 44,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final b in buckets)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text('${b.positivity}%',
                              style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          TweenAnimationBuilder<double>(
                            tween: Tween(
                                begin: 0, end: b.positivity / 100),
                            duration: const Duration(milliseconds: 700),
                            curve: Curves.easeOutCubic,
                            builder: (context, t, _) => Container(
                              height: (barAreaHeight * t).clamp(2, barAreaHeight),
                              decoration: BoxDecoration(
                                color: _barColor(b.positivity),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(b.shortLabel,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 9)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _reportSection(List<_Bucket> buckets) {
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.auto_awesome, size: 16, color: _green),
              SizedBox(width: 6),
              Text('AI TREND ANALYSIS',
                  style: TextStyle(
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 1)),
            ],
          ),
          const SizedBox(height: 12),
          if (_reportLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Column(children: [
                  CircularProgressIndicator(color: _green),
                  SizedBox(height: 12),
                  Text('Analyzing the trend…',
                      style: TextStyle(color: Colors.grey, fontSize: 13)),
                ]),
              ),
            )
          else if (_report != null) ...[
            _trendBody(_report!),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _generate(buckets),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Regenerate'),
                style: TextButton.styleFrom(foregroundColor: _green),
              ),
            ),
          ] else ...[
            const Text(
              'Let AI read the period-by-period data above and explain how the '
              'emotional and heart-rate picture is changing over time.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style:
                      const TextStyle(color: Color(0xFFFF4040), fontSize: 12)),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _generate(buckets),
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('Generate AI Trend Analysis'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _trendBody(AiTrendReport r) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(r.headline,
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 15, height: 1.3)),
        const SizedBox(height: 10),
        Text(r.analysis, style: const TextStyle(fontSize: 13, height: 1.4)),
        const SizedBox(height: 16),
        InsightBulletList(
            title: 'What is going well',
            icon: Icons.trending_up,
            color: _green,
            items: r.positives),
        if (r.positives.isNotEmpty) const SizedBox(height: 14),
        InsightBulletList(
            title: 'Keep an eye on',
            icon: Icons.warning_amber_rounded,
            color: _amber,
            items: r.concerns),
        if (r.concerns.isNotEmpty) const SizedBox(height: 14),
        InsightBulletList(
            title: 'Recommendations',
            icon: Icons.lightbulb_outline,
            color: const Color(0xFF00B4FF),
            items: r.recommendations),
      ],
    );
  }

  Widget _card(Widget child) => AppCard(child: child);
}

/// One weekly / monthly period of readings with derived stats.
class _Bucket {
  final String label;
  final String shortLabel;
  final List<EmotionReading> readings;

  _Bucket({
    required this.label,
    required this.shortLabel,
    required this.readings,
  });

  int get total => readings.length;

  int get positivity {
    if (readings.isEmpty) return 0;
    final pos = readings
        .where((r) => _AdminAiTrendsScreenState._positive.contains(r.emotion))
        .length;
    return (pos / total * 100).round();
  }

  String get dominant {
    final counts = <String, int>{};
    for (final r in readings) {
      counts[r.emotion] = (counts[r.emotion] ?? 0) + 1;
    }
    if (counts.isEmpty) return '—';
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  int get avgHr {
    final hr = readings.where((r) => r.hr > 0).map((r) => r.hr).toList();
    if (hr.isEmpty) return 0;
    return (hr.reduce((a, b) => a + b) / hr.length).round();
  }
}
