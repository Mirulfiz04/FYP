import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../services/admin_service.dart';
import '../emotion_analytics_screen.dart';

class AdminAnalyticsScreen extends StatefulWidget {
  const AdminAnalyticsScreen({super.key});

  @override
  State<AdminAnalyticsScreen> createState() => _AdminAnalyticsScreenState();
}

class _AdminAnalyticsScreenState extends State<AdminAnalyticsScreen> {
  final _admin = AdminService();
  AdminStats? _stats;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final stats = await _admin.fetchStats();
      if (mounted) setState(() => _stats = stats);
    } catch (_) {
      // best effort
    } finally {
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

  String _fmtDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}h ${m}m ${s}s' : '${m}m ${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final s = _stats;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics Dashboard'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF00DC64)))
          : s == null
              ? const Center(
                  child: Text('Could not load analytics',
                      style: TextStyle(color: Colors.grey)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _section('USAGE'),
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        childAspectRatio: 1.7,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        children: [
                          _stat('Total users', '${s.totalUsers}',
                              Icons.people_outline, const Color(0xFF00B4FF)),
                          _stat(
                              'Admins',
                              '${s.totalAdmins}',
                              Icons.admin_panel_settings_outlined,
                              const Color(0xFF00B4FF)),
                          _stat(
                              'Total sessions',
                              '${s.totalSessions}',
                              Icons.event_note_outlined,
                              const Color(0xFF9B30FF)),
                          _stat('Active now', '${s.activeSessions}',
                              Icons.sensors, const Color(0xFF00DC64)),
                          _stat(
                              'Completed',
                              '${s.completedSessions}',
                              Icons.check_circle_outline,
                              const Color(0xFF00DC64)),
                          _stat('Total readings', '${s.totalReadings}',
                              Icons.insights_outlined, const Color(0xFFFFA500)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _card(
                        child: Row(
                          children: [
                            const Icon(Icons.timer_outlined,
                                color: Colors.grey),
                            const SizedBox(width: 12),
                            const Expanded(
                                child: Text('Average session length')),
                            Text(_fmtDuration(s.avgSessionDuration),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      _section('EMOTION DISTRIBUTION'),
                      _card(child: _emotionChart(s)),
                      const SizedBox(height: 24),
                      _section('BY USER — WHO FELT WHAT'),
                      _perUserList(s),
                    ],
                  ),
                ),
    );
  }

  Widget _perUserList(AdminStats s) {
    if (s.perUser.isEmpty) {
      return _card(
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(
              child: Text('No attributed readings yet',
                  style: TextStyle(color: Colors.grey))),
        ),
      );
    }
    return Column(
      children: s.perUser.map((u) {
        final color = _emotionColor(u.dominantEmotion);
        final tappable = u.userId != null;
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: const Color(0xFF00DC64).withValues(alpha: 0.15),
              backgroundImage:
                  (u.avatarUrl != null && u.avatarUrl!.isNotEmpty)
                      ? NetworkImage(u.avatarUrl!)
                      : null,
              child: (u.avatarUrl == null || u.avatarUrl!.isEmpty)
                  ? const Icon(Icons.person, color: Color(0xFF00DC64))
                  : null,
            ),
            title: Text(u.label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Row(
              children: [
                Text('${u.readingCount} readings',
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
                if (u.avgHr > 0) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.favorite, size: 11, color: Color(0xFFFF4040)),
                  const SizedBox(width: 2),
                  Text('${u.avgHr} bpm avg',
                      style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ],
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(u.dominantEmotion,
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 11)),
            ),
            onTap: tappable
                ? () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => EmotionAnalyticsScreen(
                          userId: u.userId!,
                          title: u.label,
                          avatarUrl: u.avatarUrl,
                        ),
                      ),
                    )
                : null,
          ),
        );
      }).toList(),
    );
  }

  Widget _emotionChart(AdminStats s) {
    final counts = s.emotionCounts;
    if (counts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
            child:
                Text('No readings yet', style: TextStyle(color: Colors.grey))),
      );
    }
    final total = counts.values.fold(0, (a, b) => a + b);
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      children: [
        SizedBox(
          height: 170,
          child: Row(
            children: [
              SizedBox(
                width: 160,
                child: PieChart(PieChartData(
                  centerSpaceRadius: 32,
                  sectionsSpace: 2,
                  sections: entries.map((e) {
                    final pct = e.value / total;
                    return PieChartSectionData(
                      value: e.value.toDouble(),
                      color: _emotionColor(e.key),
                      radius: 58,
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
                    final pct = (e.value / total * 100).toStringAsFixed(1);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          CircleAvatar(
                              radius: 5, backgroundColor: _emotionColor(e.key)),
                          const SizedBox(width: 6),
                          Text(e.key,
                              style: TextStyle(
                                  color: _emotionColor(e.key), fontSize: 12)),
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
        const SizedBox(height: 8),
        Text('Based on the latest ${s.emotionSampleSize} readings',
            style: const TextStyle(color: Colors.grey, fontSize: 11)),
      ],
    );
  }

  Widget _section(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10, left: 2),
        child: Text(text,
            style: const TextStyle(
                color: Colors.grey,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 1)),
      );

  Widget _stat(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(value,
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
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
}
