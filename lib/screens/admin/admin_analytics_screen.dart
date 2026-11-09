import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../services/admin_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui_kit.dart';
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

  Color _emotionColor(String e) => MedsColors.emotion(e);

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
                      const SectionHeader(
                          title: 'Usage',
                          icon: Icons.bar_chart,
                          color: MedsColors.blue),
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        childAspectRatio: 1.55,
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
                      const SectionHeader(
                          title: 'Emotion distribution',
                          icon: Icons.pie_chart_outline,
                          color: MedsColors.purple),
                      _card(child: _emotionChart(s)),
                      const SizedBox(height: 24),
                      const SectionHeader(
                          title: 'By user — who felt what',
                          icon: Icons.people_alt_outlined,
                          color: MedsColors.teal),
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
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AppCard(
            padding: const EdgeInsets.all(6),
            child: ListTile(
            leading: CircleAvatar(
              backgroundColor: medsGreen.withValues(alpha: 0.15),
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
            trailing: Pill(text: u.dominantEmotion, color: color),
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

  Widget _stat(String label, String value, IconData icon, Color color) {
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 8),
          Text(value,
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          Text(label,
              style: const TextStyle(color: MedsColors.muted, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) => AppCard(child: child);
}
