import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/emotion_reading.dart';
import '../models/session_analytics.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ai_insight_card.dart';
import '../widgets/emotion_distribution_card.dart';
import '../widgets/ui_kit.dart';

const Color _accent = Color(0xFF6A5AE0);

enum _Period { today, week, month, custom }

/// Per-user emotion + heart-rate analytics dashboard. Reused by the user (their
/// own data) and by an admin viewing any user. Analytics are computed via the
/// shared [SessionAnalytics] — not inside build().
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
  List<EmotionReading> _all = [];
  bool _loading = true;

  _Period _period = _Period.week;
  DateTime? _customStart, _customEnd;

  List<EmotionReading> _filtered = [];
  SessionAnalytics _analytics = SessionAnalytics.from(const []);
  int _sessions = 0;
  int? _latestBpm;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _svc.fetchReadingsForUser(widget.userId, limit: 2000);
      if (!mounted) return;
      _all = data;
      _recompute();
      setState(() => _loading = false);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setPeriod(_Period p, {DateTime? start, DateTime? end}) {
    _period = p;
    if (p == _Period.custom) {
      _customStart = start;
      _customEnd = end;
    }
    setState(_recompute);
  }

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
    );
    if (range != null) {
      _setPeriod(_Period.custom, start: range.start, end: range.end);
    }
  }

  void _recompute() {
    final range = _range();
    _filtered = _all.where((r) {
      if (range == null) return true;
      final t = r.createdAt.toLocal();
      return !t.isBefore(range.$1) && !t.isAfter(range.$2);
    }).toList();
    // fetchReadingsForUser returns newest-first; SessionAnalytics expects
    // oldest-first so its trend + recent come out chronological/newest.
    _analytics = SessionAnalytics.from(_filtered.reversed.toList());
    _sessions =
        _filtered.map((r) => r.sessionId).whereType<String>().toSet().length;
    _latestBpm = _analytics.hrTrend.isEmpty ? null : _analytics.hrTrend.last.bpm;
  }

  (DateTime, DateTime)? _range() {
    final now = DateTime.now();
    switch (_period) {
      case _Period.today:
        return (DateTime(now.year, now.month, now.day), now);
      case _Period.week:
        final monday = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: now.weekday - 1));
        return (monday, now);
      case _Period.month:
        return (DateTime(now.year, now.month, 1), now);
      case _Period.custom:
        if (_customStart == null || _customEnd == null) return null;
        return (
          DateTime(_customStart!.year, _customStart!.month, _customStart!.day),
          DateTime(_customEnd!.year, _customEnd!.month, _customEnd!.day, 23, 59, 59),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Emotion Analytics'),
        centerTitle: true,
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh), tooltip: 'Refresh', onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : RefreshIndicator(
              onRefresh: _load,
              color: _accent,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _userCard(),
                  const SizedBox(height: 14),
                  _periodFilter(),
                  const SizedBox(height: 14),
                  if (_analytics.totalReadings == 0)
                    const SizedBox(
                      height: 320,
                      child: EmptyState(
                        icon: Icons.insights_outlined,
                        title: 'No readings in this period',
                        message:
                            'Run a detection session, or pick a different period.',
                        color: MedsColors.purple,
                      ),
                    )
                  else ...[
                    _summaryCards(),
                    const SizedBox(height: 14),
                    AiInsightCard(
                      key: ValueKey('${_period.name}_${_filtered.length}'),
                      title: 'AI WELLNESS INSIGHT',
                      buttonLabel: 'Generate AI Insights',
                      fetchReadings: () async => _filtered,
                    ),
                    const SizedBox(height: 14),
                    EmotionDistributionCard(
                      distribution: _analytics.distribution,
                      totalReadings: _analytics.totalReadings,
                    ),
                    const SizedBox(height: 14),
                    _heartRateOverview(),
                    const SizedBox(height: 14),
                    _moodTimeline(),
                    const SizedBox(height: 14),
                    _wellnessTip(),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _userCard() {
    final hasAvatar = (widget.avatarUrl ?? '').isNotEmpty;
    return AppCard(
      child: Row(
        children: [
          CircleAvatar(
            radius: 27,
            backgroundColor: MedsColors.greenDark.withValues(alpha: 0.15),
            backgroundImage: hasAvatar ? NetworkImage(widget.avatarUrl!) : null,
            child: hasAvatar
                ? null
                : const Icon(Icons.person, color: MedsColors.greenDark, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.bold)),
                if (widget.subtitle != null)
                  Text(widget.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: MedsColors.muted, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _periodFilter() {
    const labels = {
      _Period.today: 'Today',
      _Period.week: 'This Week',
      _Period.month: 'This Month',
      _Period.custom: 'Custom',
    };
    return AppCard(
      padding: const EdgeInsets.all(6),
      child: Row(
        children: labels.entries.map((e) {
          final selected = _period == e.key;
          return Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => e.key == _Period.custom
                  ? _pickCustom()
                  : _setPeriod(e.key),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  gradient: selected
                      ? const LinearGradient(
                          colors: [Color(0xFF8B7CF6), Color(0xFF6A5AE0)])
                      : null,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  e.value,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : MedsColors.muted,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _summaryCards() {
    final a = _analytics;
    return Row(
      children: [
        Expanded(
          child: _stat(Icons.mood, MedsColors.purple, 'Dominant Emotion',
              a.dominantEmotion, MedsColors.purple),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _stat(Icons.favorite, MedsColors.red, 'Avg Heart Rate',
              a.avgBpm != null ? '${a.avgBpm} BPM' : '--', MedsColors.red),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _stat(Icons.trending_up, MedsColors.amber, 'Stress Level',
              a.stressIndicator, MedsColors.stress(a.stressIndicator)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _stat(Icons.calendar_month, MedsColors.blue, 'Sessions',
              '$_sessions', MedsColors.blue),
        ),
      ],
    );
  }

  Widget _stat(IconData icon, Color color, String label, String value,
      Color valueColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: softShadow(context),
      ),
      child: Column(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 7),
          SizedBox(
            height: 24,
            child: Center(
              child: Text(label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 10, height: 1.05, color: MedsColors.muted)),
            ),
          ),
          const SizedBox(height: 4),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.bold, color: valueColor)),
        ],
      ),
    );
  }

  // ---- Heart Rate Overview ------------------------------------------------

  Widget _heartRateOverview() {
    final a = _analytics;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Heart Rate Overview',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const Spacer(),
              const Icon(Icons.favorite, color: MedsColors.red, size: 19),
            ],
          ),
          const SizedBox(height: 12),
          if (!a.hasValidHr)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('No valid heart-rate data for this period.',
                  style: TextStyle(color: MedsColors.muted, fontSize: 13)),
            )
          else ...[
            Row(
              children: [
                _mini('Average', a.avgBpm!, MedsColors.red),
                const SizedBox(width: 8),
                _mini('Min', a.minBpm!, MedsColors.greenDark),
                const SizedBox(width: 8),
                _mini('Max', a.maxBpm!, MedsColors.red),
                const SizedBox(width: 8),
                _mini('Latest', _latestBpm ?? a.avgBpm!, MedsColors.blue),
              ],
            ),
            const SizedBox(height: 12),
            const Text('Beats per minute over time',
                style: TextStyle(color: MedsColors.muted, fontSize: 11.5)),
            const SizedBox(height: 8),
            SizedBox(height: 140, child: LineChart(_hrChart(a.hrTrend))),
          ],
        ],
      ),
    );
  }

  Widget _mini(String label, int value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: MedsColors.lightBg,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Column(
          children: [
            Text('$value',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            Text(label,
                style: const TextStyle(color: MedsColors.muted, fontSize: 10.5)),
          ],
        ),
      ),
    );
  }

  LineChartData _hrChart(List<HrPoint> pts) {
    final values = pts.map((p) => p.bpm).toList();
    final lo = values.reduce((a, b) => a < b ? a : b);
    final hi = values.reduce((a, b) => a > b ? a : b);
    return LineChartData(
      minX: 0,
      maxX: (pts.length - 1).toDouble().clamp(1, double.infinity),
      minY: (lo - 6).toDouble(),
      maxY: (hi + 6).toDouble(),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) =>
            FlLine(color: Theme.of(context).dividerColor, strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            interval: (((hi + 6) - (lo - 6)) / 2).clamp(1, 999),
            getTitlesWidget: (v, _) => Text('${v.toInt()}',
                style: const TextStyle(color: MedsColors.muted, fontSize: 10)),
          ),
        ),
      ),
      lineTouchData: const LineTouchData(enabled: false),
      lineBarsData: [
        LineChartBarData(
          spots: [
            for (var i = 0; i < pts.length; i++)
              FlSpot(i.toDouble(), pts[i].bpm.toDouble()),
          ],
          isCurved: true,
          color: MedsColors.red,
          barWidth: 2.5,
          dotData: const FlDotData(show: false),
          belowBarData:
              BarAreaData(show: true, color: MedsColors.red.withValues(alpha: 0.10)),
        ),
      ],
    );
  }

  // ---- Mood timeline ------------------------------------------------------

  Widget _moodTimeline() {
    final recent = _analytics.recent;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.schedule, color: _accent, size: 18),
              SizedBox(width: 8),
              Text('Mood Timeline ',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              Text('(Recent)',
                  style: TextStyle(color: MedsColors.muted, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 10),
          ...recent.map((r) {
            final color = MedsColors.emotion(r.emotion);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  Text(MedsColors.emoji(r.emotion),
                      style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 60,
                    child: Text(r.emotion,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: (r.confidence / 100).clamp(0, 1),
                        minHeight: 7,
                        backgroundColor: color.withValues(alpha: 0.15),
                        valueColor: AlwaysStoppedAnimation(color),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 38,
                    child: Text('${r.confidence.round()}%',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                  ),
                  const SizedBox(width: 8),
                  Text(DateFormat('HH:mm:ss').format(r.createdAt.toLocal()),
                      style:
                          const TextStyle(color: MedsColors.muted, fontSize: 11)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ---- Wellness tip -------------------------------------------------------

  Widget _wellnessTip() {
    final a = _analytics;
    final hrPart =
        a.hasValidHr ? 'Your heart rate is stable overall. ' : '';
    final hasAngry =
        a.distribution.any((s) => s.emotion == 'Angry' && s.count > 0);
    final advice = hasAngry
        ? 'Consider taking short breaks if angry moments increase.'
        : 'Keep up your balanced routine and check back regularly.';
    final tip =
        '$hrPart${a.dominantEmotion} mood has been most frequent this period. '
        '$advice';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MedsColors.greenDark.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: MedsColors.greenDark.withValues(alpha: 0.25)),
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
                    Icon(Icons.eco, color: MedsColors.greenDark, size: 18),
                    SizedBox(width: 7),
                    Text('Wellness Tip',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: MedsColors.greenDark)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(tip,
                    style: const TextStyle(
                        fontSize: 12.5, height: 1.5, color: MedsColors.lightText)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.monitor_heart,
              color: MedsColors.greenDark, size: 38),
        ],
      ),
    );
  }
}
