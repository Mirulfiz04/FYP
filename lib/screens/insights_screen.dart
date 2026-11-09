import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../models/emotion_reading.dart';
import '../services/auth_service.dart';
import '../services/insights_service.dart';
import '../theme/app_theme.dart';
import '../viewmodels/insights_view_model.dart';
import '../widgets/app_nav_drawer.dart';
import '../widgets/emotion_distribution_chart.dart';
import '../widgets/insights_ai_card.dart';
import '../widgets/insights_empty_state.dart';
import '../widgets/insights_summary_cards.dart';
import '../widgets/notification_bell.dart';
import '../widgets/weekly_overview_card.dart';
import '../widgets/weekly_trend_chart.dart';
import 'emotion_analytics_screen.dart';
import 'notifications_screen.dart';
import 'session_readiness_screen.dart';

const Color _accent = Color(0xFF6A5AE0);

/// The Insights tab: period filter, summary cards, weekly trend chart, emotion
/// distribution, AI insight, weekly overview and emotional pattern.
class InsightsScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  final ValueChanged<int> onOpenTab;

  const InsightsScreen({
    super.key,
    required this.cameras,
    required this.onOpenTab,
  });

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  final _vm = InsightsViewModel(source: SupabaseInsightsSource());
  final _auth = AuthService();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  String? _name;
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    _vm.load();
    _loadProfile();
  }

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final p = await _auth.loadProfile();
      if (mounted) {
        setState(() {
          _name = p.name?.isNotEmpty == true ? p.name : p.email;
          _avatarUrl = p.avatarUrl;
        });
      }
    } catch (_) {}
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
    );
    if (range != null) {
      _vm.setPeriod(InsightsPeriod.custom,
          start: range.start, end: range.end);
    }
  }

  Future<void> _startSession() async {
    final ran = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SessionReadinessScreen(
          cameras: widget.cameras,
          onOpenTab: widget.onOpenTab,
        ),
      ),
    );
    if (ran == true) _vm.refresh();
  }

  void _openTrends() {
    final uid = _auth.currentUser?.id;
    if (uid == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EmotionAnalyticsScreen(
        userId: uid,
        title: 'Trends',
        subtitle: 'Your emotion & heart-rate analytics',
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: AppNavDrawer(
        name: _name,
        avatarUrl: _avatarUrl,
        onOpenTab: widget.onOpenTab,
        onNotifications: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const NotificationsScreen())),
        onSignOut: _auth.signOut,
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _vm,
          builder: (context, _) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Column(
                    children: [
                      _header(),
                      const SizedBox(height: 16),
                      _periodRow(),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _vm.refresh,
                    color: _accent,
                    child: _content(),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            boxShadow: softShadow(context),
          ),
          child: IconButton(
            icon: const Icon(Icons.menu, color: _accent),
            tooltip: 'Menu',
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Insights',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              SizedBox(height: 2),
              Text('Understand your emotions & wellness better.',
                  style: TextStyle(color: MedsColors.muted, fontSize: 12.5)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            boxShadow: softShadow(context),
          ),
          child: const NotificationBell(),
        ),
      ],
    );
  }

  Widget _periodRow() {
    const labels = {
      InsightsPeriod.today: 'Today',
      InsightsPeriod.week: 'This Week',
      InsightsPeriod.month: 'This Month',
      InsightsPeriod.custom: 'Custom',
    };
    return Row(
      children: [
        const Text('Period',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(width: 10),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: labels.entries.map((e) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _chip(
                    label: e.value,
                    selected: _vm.period == e.key,
                    onTap: () {
                      if (e.key == InsightsPeriod.custom) {
                        _pickCustomRange();
                      } else {
                        _vm.setPeriod(e.key);
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: IconButton(
            icon: const Icon(Icons.calendar_today_outlined,
                color: _accent, size: 20),
            tooltip: 'Custom range',
            onPressed: _pickCustomRange,
          ),
        ),
      ],
    );
  }

  Widget _chip(
      {required String label,
      required bool selected,
      required VoidCallback onTap}) {
    return Material(
      color: selected ? _accent : Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: selected
                ? null
                : Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Text(label,
              style: TextStyle(
                  color: selected ? Colors.white : MedsColors.muted,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
        ),
      ),
    );
  }

  Widget _content() {
    if (_vm.loading && _vm.data.validSessions == 0 && !_vm.hasAnyCompletedSession) {
      return _scroll([
        const SizedBox(
            height: 320,
            child: Center(child: CircularProgressIndicator(color: _accent))),
      ]);
    }
    if (_vm.error != null) {
      return _scroll([
        SizedBox(height: 360, child: InsightsEmptyState.error(_vm.refresh)),
      ]);
    }
    if (!_vm.hasAnyCompletedSession) {
      return _scroll([
        SizedBox(
            height: 380,
            child: InsightsEmptyState.noSessions(_startSession)),
      ]);
    }
    if (!_vm.data.hasData) {
      return _scroll([
        SizedBox(
            height: 380,
            child: InsightsEmptyState.insufficient(_startSession)),
      ]);
    }

    final data = _vm.data;
    return _scroll([
      InsightsSummaryCards(data: data),
      const SizedBox(height: 8),
      Text('Based on ${data.validSessions} valid sessions',
          style: const TextStyle(color: MedsColors.muted, fontSize: 11.5)),
      const SizedBox(height: 16),
      WeeklyTrendChart(
        points: data.trend,
        granularity: _vm.granularity,
        onGranularityChanged: _vm.setGranularity,
      ),
      const SizedBox(height: 16),
      EmotionDistributionChart(
        slices: data.distribution,
        totalDetections: data.totalValidDetections,
      ),
      const SizedBox(height: 16),
      InsightsAiCard(
        enough: data.enoughForInsight,
        regenerateKey: '${_vm.period.name}:${data.validSessions}:${data.avgBpm}',
        fetchReadings: () async => List<EmotionReading>.of(data.aiReadings),
      ),
      const SizedBox(height: 16),
      WeeklyOverviewCard(data: data, onOpenTrends: _openTrends),
      const SizedBox(height: 16),
      EmotionalPatternCard(
        pattern: data.emotionalPattern ??
            'Complete more sessions to reveal your emotional patterns.',
        onTap: _openTrends,
      ),
    ]);
  }

  Widget _scroll(List<Widget> children) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: children,
    );
  }
}
