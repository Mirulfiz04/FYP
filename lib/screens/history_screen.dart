import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/emotion_reading.dart';
import '../services/supabase_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
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
    final data = await _svc.fetchHistory();
    if (mounted) {
      setState(() {
        _readings = data;
        _loading = false;
      });
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

  Map<String, int> get _counts {
    final map = <String, int>{};
    for (final r in _readings) {
      map[r.emotion] = (map[r.emotion] ?? 0) + 1;
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('History  (${_readings.length} readings)'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF00DC64)))
          : _readings.isEmpty
              ? const Center(
                  child: Text('No history yet.',
                      style: TextStyle(color: Colors.grey, fontSize: 16)))
              : Column(
                  children: [
                    _PieChart(counts: _counts, colorOf: _emotionColor),
                    _SummaryChips(
                        counts: _counts,
                        total: _readings.length,
                        colorOf: _emotionColor),
                    Expanded(
                        child: _ReadingList(
                            readings: _readings, colorOf: _emotionColor)),
                  ],
                ),
    );
  }
}

class _PieChart extends StatelessWidget {
  final Map<String, int> counts;
  final Color Function(String) colorOf;

  const _PieChart({required this.counts, required this.colorOf});

  @override
  Widget build(BuildContext context) {
    if (counts.isEmpty) return const SizedBox.shrink();
    final total = counts.values.fold(0, (a, b) => a + b);
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final sections = entries.map((e) {
      final pct = e.value / total;
      return PieChartSectionData(
        value: e.value.toDouble(),
        color: colorOf(e.key),
        title: pct >= 0.08 ? '${(pct * 100).toStringAsFixed(0)}%' : '',
        titleStyle:
            const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
        radius: 60,
      );
    }).toList();

    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: SizedBox(
        height: 160,
        child: Row(
          children: [
            SizedBox(
              width: 160,
              child: PieChart(PieChartData(
                sections: sections,
                centerSpaceRadius: 30,
                sectionsSpace: 2,
              )),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: entries.map((e) {
                  final pct = (e.value / total * 100).toStringAsFixed(1);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        CircleAvatar(
                            radius: 5, backgroundColor: colorOf(e.key)),
                        const SizedBox(width: 6),
                        Text(e.key,
                            style: TextStyle(
                                color: colorOf(e.key), fontSize: 12)),
                        const Spacer(),
                        Text('$pct%',
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
    );
  }
}

class _SummaryChips extends StatelessWidget {
  final Map<String, int> counts;
  final int total;
  final Color Function(String) colorOf;

  const _SummaryChips(
      {required this.counts, required this.total, required this.colorOf});

  @override
  Widget build(BuildContext context) {
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Container(
      width: double.infinity,
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: sorted.map((e) {
          final pct = (e.value / total * 100).toStringAsFixed(0);
          final col = colorOf(e.key);
          return Chip(
            label: Text('${e.key}  $pct%',
                style: TextStyle(
                    color: col,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
            backgroundColor: col.withValues(alpha: 0.10),
            side: BorderSide(color: col.withValues(alpha: 0.35)),
            visualDensity: VisualDensity.compact,
          );
        }).toList(),
      ),
    );
  }
}

class _ReadingList extends StatelessWidget {
  final List<EmotionReading> readings;
  final Color Function(String) colorOf;

  const _ReadingList({required this.readings, required this.colorOf});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd MMM  HH:mm:ss');
    return ListView.separated(
      itemCount: readings.length,
      separatorBuilder: (_, __) =>
          Divider(height: 1, color: Theme.of(context).dividerColor),
      itemBuilder: (context, i) {
        final r = readings[i];
        final col = colorOf(r.emotion);
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: col.withValues(alpha: 0.18),
            child: Text(r.emotion.isEmpty ? '?' : r.emotion[0],
                style:
                    TextStyle(color: col, fontWeight: FontWeight.bold)),
          ),
          title: Row(
            children: [
              Text(r.emotion,
                  style:
                      TextStyle(color: col, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Text('${r.confidence.toStringAsFixed(1)}%',
                  style:
                      const TextStyle(color: Colors.grey, fontSize: 13)),
            ],
          ),
          subtitle: Row(
            children: [
              Icon(Icons.favorite, size: 11, color: Colors.red.shade300),
              const SizedBox(width: 3),
              Text(r.hr > 0 ? '${r.hr} bpm' : '---',
                  style: const TextStyle(
                      color: Colors.grey, fontSize: 12)),
              const SizedBox(width: 10),
              Icon(Icons.water_drop,
                  size: 11, color: Colors.blue.shade300),
              const SizedBox(width: 3),
              Text(r.spo2 > 0 ? '${r.spo2}%' : '---%',
                  style: const TextStyle(
                      color: Colors.grey, fontSize: 12)),
            ],
          ),
          trailing: Text(fmt.format(r.createdAt.toLocal()),
              style:
                  const TextStyle(color: Colors.grey, fontSize: 11)),
        );
      },
    );
  }
}
