import 'package:flutter/material.dart';

import '../../models/admin_insights_model.dart';
import '../../theme/app_theme.dart';
import '../../viewmodels/admin_insights_view_model.dart';
import '../../widgets/admin/admin_header.dart';
import '../../widgets/admin/admin_weekly_trend_chart.dart';
import '../../widgets/admin/dashboard_metric_card.dart' show MetricTrendPill;
import '../../widgets/admin/emotion_distribution_card.dart';
import '../../widgets/admin/insight_metric_card.dart';
import '../../widgets/admin/risk_user_card.dart';
import '../../widgets/admin/session_performance_card.dart';
import '../../widgets/ui_kit.dart';
import '../notifications_screen.dart';
import 'admin_ai_report_screen.dart';
import 'admin_emotion_detail_screen.dart';
import 'admin_performance_detail_screen.dart';
import 'admin_session_detail_screen.dart';

/// Admin Insights — platform-wide emotional trends, AI findings and session
/// performance. State lives in [AdminInsightsViewModel]; data is loaded through
/// a service, never queried directly in the widgets.
class AdminInsightsScreen extends StatefulWidget {
  /// Injected in tests; defaults to a view-model backed by the real service.
  final AdminInsightsViewModel? viewModel;

  /// Provided by [AdminShell] to switch bottom-nav tabs.
  final ValueChanged<int>? onOpenTab;

  const AdminInsightsScreen({super.key, this.viewModel, this.onOpenTab});

  @override
  State<AdminInsightsScreen> createState() => _AdminInsightsScreenState();
}

class _AdminInsightsScreenState extends State<AdminInsightsScreen> {
  late final AdminInsightsViewModel _vm = widget.viewModel ?? AdminInsightsViewModel();
  AdminChartType _chartType = AdminChartType.line;

  @override
  void initState() {
    super.initState();
    _vm.load();
  }

  @override
  void dispose() {
    // Only dispose a view-model we created ourselves.
    if (widget.viewModel == null) _vm.dispose();
    super.dispose();
  }

  // ---- Navigation ---------------------------------------------------------

  void _push(Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  void _openTab(int i) => widget.onOpenTab?.call(i);

  Future<void> _selectPeriod(AdminInsightsPeriod p) async {
    if (p == AdminInsightsPeriod.custom) {
      final now = DateTime.now();
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 3),
        lastDate: now,
        initialDateRange: DateTimeRange(
            start: now.subtract(const Duration(days: 7)), end: now),
      );
      if (range == null) return;
      await _vm.setPeriod(
        AdminInsightsPeriod.custom,
        customStart:
            DateTime(range.start.year, range.start.month, range.start.day),
        customEnd: DateTime(
            range.end.year, range.end.month, range.end.day, 23, 59, 59),
      );
      return;
    }
    await _vm.setPeriod(p);
  }

  Future<void> _openFilterSheet() async {
    final picked = await showModalBottomSheet<AdminInsightsPeriod>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Filter by period',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
            ...AdminInsightsPeriod.values.map((p) => ListTile(
                  leading: Icon(
                    p == AdminInsightsPeriod.custom
                        ? Icons.calendar_today_outlined
                        : Icons.schedule,
                    color: _vm.period == p
                        ? MedsColors.purple
                        : MedsColors.muted,
                  ),
                  title: Text(p.label),
                  trailing: _vm.period == p
                      ? const Icon(Icons.check, color: MedsColors.purple)
                      : null,
                  onTap: () => Navigator.pop(ctx, p),
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null) await _selectPeriod(picked);
  }

  void _openRiskUser(RiskUser u) {
    if (u.latestSession != null) {
      _push(AdminSessionDetailScreen(
        session: u.latestSession!,
        userName: u.name,
        avatarUrl: u.avatarUrl,
        initials: u.initials,
      ));
    } else {
      _openTab(3);
    }
  }

  // ---- Build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: _vm,
          builder: (context, _) {
            return RefreshIndicator(
              color: MedsColors.purple,
              onRefresh: _vm.refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  _header(),
                  const SizedBox(height: 16),
                  _periodFilter(),
                  const SizedBox(height: 16),
                  if (_vm.error != null && _vm.data == null)
                    _ErrorView(onRetry: _vm.load)
                  else if (_vm.data == null)
                    const _LoadingView()
                  else
                    ..._content(_vm.data!),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Insights',
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                      color: MedsColors.lightText)),
              SizedBox(height: 4),
              Text('Analyze emotional trends, AI findings, and platform performance',
                  style: TextStyle(color: MedsColors.muted, fontSize: 12.5)),
            ],
          ),
        ),
        const SizedBox(width: 10),
        AdminHeaderButton(
          icon: Icons.refresh,
          tooltip: 'Refresh',
          busy: _vm.refreshing,
          onTap: _vm.refreshing ? null : _vm.refresh,
        ),
        const SizedBox(width: 8),
        AdminNotificationButton(
            onTap: () => _push(const NotificationsScreen())),
        const SizedBox(width: 8),
        AdminHeaderButton(
          icon: Icons.tune,
          tooltip: 'Filter',
          onTap: _openFilterSheet,
        ),
      ],
    );
  }

  Widget _periodFilter() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: AdminInsightsPeriod.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final p = AdminInsightsPeriod.values[i];
          final selected = _vm.period == p;
          return _PeriodChip(
            label: p.label,
            selected: selected,
            showCalendar: p == AdminInsightsPeriod.custom,
            onTap: () => _selectPeriod(p),
          );
        },
      ),
    );
  }

  List<Widget> _content(AdminInsightsData d) {
    return [
      _metrics(d),
      const SizedBox(height: 16),
      AdminWeeklyTrendChart(
        points: d.trend,
        chartType: _chartType,
        onChartTypeChanged: (t) => setState(() => _chartType = t),
      ),
      const SizedBox(height: 16),
      EmotionDistributionCard(
        slices: d.emotions,
        total: d.totalSessions,
        centerLabel: 'Sessions',
        onViewAll: () => _push(AdminEmotionDetailScreen(
            emotions: d.emotions, total: d.totalSessions)),
      ),
      const SizedBox(height: 16),
      _AiInsightPanel(
        data: d,
        onReport: () => _push(const AdminAiReportScreen()),
      ),
      const SizedBox(height: 16),
      TopAtRiskUsersCard(
        users: d.atRiskUsers,
        onOpenUser: _openRiskUser,
        onViewAll: () => _openTab(3),
      ),
      const SizedBox(height: 16),
      SessionPerformanceCard(
        performance: d.performance,
        comparison: _vm.period.comparison,
        onDetails: () => _push(AdminPerformanceDetailScreen(
            performance: d.performance, comparison: _vm.period.comparison)),
      ),
    ];
  }

  Widget _metrics(AdminInsightsData d) {
    final comparison = _vm.period.comparison;
    final cards = <Widget>[
      InsightMetricCard(
        icon: Icons.graphic_eq,
        color: MedsColors.purple,
        label: 'Avg Stress Level',
        value: '${d.avgStress}',
        unit: '/100',
        footer: MetricTrendPill(
          percent: d.avgStressDeltaPct,
          hasBaseline: true,
          higherIsBetter: false,
          comparison: comparison,
        ),
      ),
      InsightMetricCard(
        icon: Icons.favorite,
        color: MedsColors.coral,
        label: 'Avg Heart Rate',
        value: '${d.avgBpm}',
        unit: 'BPM',
        footer: MetricTrendPill(
          percent: d.avgBpmDeltaPct,
          hasBaseline: true,
          higherIsBetter: false,
          comparison: comparison,
        ),
      ),
      InsightMetricCard(
        icon: Icons.sentiment_satisfied_alt_outlined,
        color: MedsColors.greenDark,
        label: 'Dominant Emotion',
        value: d.dominantEmotion,
        footer: MetricCaption(
          highlight: '${d.dominantPercent}%',
          text: 'of sessions',
          color: MedsColors.greenDark,
        ),
      ),
      InsightMetricCard(
        icon: Icons.warning_amber_rounded,
        color: MedsColors.amber,
        label: 'Flagged Sessions',
        value: '${d.flagged}',
        footer: MetricTrendPill(
          percent: d.flaggedDeltaPct,
          hasBaseline: true,
          higherIsBetter: false,
          comparison: comparison,
        ),
      ),
    ];
    return _MetricGrid(cards: cards);
  }
}

// ---------------------------------------------------------------------------
// Period chip
// ---------------------------------------------------------------------------

class _PeriodChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool showCalendar;
  final VoidCallback onTap;

  const _PeriodChip({
    required this.label,
    required this.selected,
    required this.showCalendar,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return Material(
      color: selected ? MedsColors.purple : surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: selected
                ? null
                : Border.all(color: MedsColors.muted.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: TextStyle(
                      color: selected ? Colors.white : MedsColors.lightText,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
              if (showCalendar) ...[
                const SizedBox(width: 6),
                Icon(Icons.calendar_today_outlined,
                    size: 14,
                    color: selected ? Colors.white : MedsColors.muted),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Responsive metric grid (IntrinsicHeight rows — never overflows)
// ---------------------------------------------------------------------------

class _MetricGrid extends StatelessWidget {
  final List<Widget> cards;
  const _MetricGrid({required this.cards});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth >= 560) {
          return IntrinsicHeight(child: _row(cards));
        }
        return Column(
          children: [
            IntrinsicHeight(child: _row(cards.sublist(0, 2))),
            const SizedBox(height: 12),
            IntrinsicHeight(child: _row(cards.sublist(2, 4))),
          ],
        );
      },
    );
  }

  Widget _row(List<Widget> children) {
    final out = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      out.add(Expanded(child: children[i]));
      if (i < children.length - 1) out.add(const SizedBox(width: 12));
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: out);
  }
}

// ---------------------------------------------------------------------------
// AI Insight panel
// ---------------------------------------------------------------------------

class _AiInsightPanel extends StatelessWidget {
  final AdminInsightsData data;
  final VoidCallback onReport;

  const _AiInsightPanel({required this.data, required this.onReport});

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
                child: const Icon(Icons.auto_awesome,
                    size: 16, color: MedsColors.purple),
              ),
              const SizedBox(width: 9),
              const Text('AI Insight',
                  style:
                      TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5)),
            ],
          ),
          const SizedBox(height: 12),
          Text(data.aiText,
              style: const TextStyle(
                  fontSize: 13.5, height: 1.5, color: MedsColors.lightText)),
          const SizedBox(height: 14),
          _HighlightRow(
            icon: Icons.trending_up,
            color: MedsColors.purple,
            label: 'Highest Stress Day',
            value: data.highestStressDay,
          ),
          const SizedBox(height: 8),
          _HighlightRow(
            icon: Icons.flag_outlined,
            color: MedsColors.amber,
            label: 'Flagged Sessions',
            value: '${data.flagged}',
          ),
          const SizedBox(height: 12),
          const Text('Analytical indicator — not a medical diagnosis.',
              style: TextStyle(
                  color: MedsColors.muted,
                  fontSize: 11,
                  fontStyle: FontStyle.italic)),
          const SizedBox(height: 10),
          InkWell(
            onTap: onReport,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 14),
              decoration: BoxDecoration(
                color: MedsColors.purple.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Flexible(
                    child: Text('View Detailed AI Report',
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: MedsColors.purple,
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5)),
                  ),
                  SizedBox(width: 6),
                  Icon(Icons.chevron_right, color: MedsColors.purple, size: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HighlightRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  const _HighlightRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13)),
          ),
          Text(value,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.bold, fontSize: 13.5)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loading + error states
// ---------------------------------------------------------------------------

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _MetricGrid(cards: List.generate(4, (_) => const InsightMetricSkeleton())),
        const SizedBox(height: 16),
        ...List.generate(
            3,
            (_) => const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: AppCard(
                    child: SizedBox(
                      height: 150,
                      child: Center(
                        child:
                            CircularProgressIndicator(color: MedsColors.purple),
                      ),
                    ),
                  ),
                )),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: EmptyState(
        icon: Icons.cloud_off_outlined,
        color: MedsColors.red,
        title: 'Could not load insights',
        message:
            'Please check your connection and try again. Your data is safe.',
        action: FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
        ),
      ),
    );
  }
}
