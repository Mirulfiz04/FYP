import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/admin_dashboard_models.dart';
import '../../services/admin_dashboard_service.dart';
import '../../services/notification_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/admin/dashboard_ai_insight_card.dart';
import '../../widgets/admin/dashboard_metric_card.dart';
import '../../widgets/admin/emotion_distribution_card.dart';
import '../../widgets/admin/platform_overview_chart.dart';
import '../../widgets/admin/recent_activity_list.dart';
import '../../widgets/ui_kit.dart';
import '../notifications_screen.dart';
import '../settings_screen.dart';
import 'admin_reports_screen.dart';
import 'admin_session_detail_screen.dart';
import 'admin_status_screen.dart';

/// Admin Dashboard — the landing tab of the admin shell. Pulls all data through
/// [AdminDashboardSource]; no Supabase calls live in the widget tree.
class AdminDashboardScreen extends StatefulWidget {
  /// Injected in tests; defaults to the real service in production.
  final AdminDashboardSource? source;

  /// Provided by [AdminShell] so quick actions can switch bottom-nav tabs.
  final ValueChanged<int>? onOpenTab;

  const AdminDashboardScreen({super.key, this.source, this.onOpenTab});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  late final AdminDashboardSource _source =
      widget.source ?? AdminDashboardService();

  DashboardData? _data;
  bool _loading = true;
  bool _refreshing = false;
  Object? _error;
  DashboardPeriod _period = DashboardPeriod.week;
  DateTime? _customStart;
  DateTime? _customEnd;
  DateTime? _lastUpdated;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool showSpinner = false}) async {
    if (_refreshing) return; // prevent repeated/overlapping refreshes
    setState(() {
      if (showSpinner) _refreshing = true;
      if (_data == null) _loading = true;
      _error = null;
    });
    try {
      final data = await _source.fetchDashboard(
        period: _period,
        customStart: _customStart,
        customEnd: _customEnd,
      );
      if (!mounted) return;
      setState(() {
        _data = data;
        _lastUpdated = DateTime.now();
      });
      if (showSpinner) {
        _snack('Dashboard updated', MedsColors.greenDark);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
      if (showSpinner) _snack('Could not refresh dashboard', MedsColors.red);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  void _snack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  Future<void> _changePeriod(DashboardPeriod p) async {
    if (p == DashboardPeriod.custom) {
      final now = DateTime.now();
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 3),
        lastDate: now,
        initialDateRange: _customStart != null && _customEnd != null
            ? DateTimeRange(start: _customStart!, end: _customEnd!)
            : DateTimeRange(
                start: now.subtract(const Duration(days: 7)), end: now),
      );
      if (range == null) return;
      _customStart = DateTime(
          range.start.year, range.start.month, range.start.day);
      _customEnd = DateTime(
          range.end.year, range.end.month, range.end.day, 23, 59, 59);
    }
    setState(() => _period = p);
    await _load(showSpinner: true);
  }

  void _openTab(int i) => widget.onOpenTab?.call(i);

  void _push(Widget screen) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => screen))
        .then((_) {
      if (mounted) _load();
    });
  }

  void _openSettings() {
    if (widget.onOpenTab != null) {
      _openTab(4);
    } else {
      _push(const SettingsScreen());
    }
  }

  void _openSession(RecentActivityItem item) => _push(AdminSessionDetailScreen(
        session: item.session,
        userName: item.userName,
        avatarUrl: item.avatarUrl,
        initials: item.initials,
      ));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: MedsColors.purple,
          onRefresh: () => _load(showSpinner: true),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              _Header(
                refreshing: _refreshing,
                onRefresh: () => _load(showSpinner: true),
                onNotifications: () => _push(const NotificationsScreen()),
                onSettings: _openSettings,
              ),
              const SizedBox(height: 18),
              if (_error != null && _data == null)
                _ErrorView(onRetry: _load)
              else ...[
                _metrics(),
                const SizedBox(height: 16),
                PlatformOverviewChart(
                  points: _data?.sessionTrend ?? const [],
                  period: _period,
                  onPeriodChanged: _changePeriod,
                ),
                const SizedBox(height: 16),
                EmotionDistributionCard(
                  slices: _data?.emotions ?? const [],
                  total: _data?.totalDetections ?? 0,
                ),
                const SizedBox(height: 16),
                DashboardAiInsightCard(
                  loading: _loading,
                  insight: _data?.aiInsight,
                  failed: _data?.aiInsightFailed ?? false,
                  onViewFull: () => _openTab(2),
                  onRetry: () => _load(showSpinner: true),
                ),
                const SizedBox(height: 16),
                RecentActivityList(
                  items: _data?.recentActivity ?? const [],
                  onOpen: _openSession,
                  onViewAll: () => _openTab(1),
                ),
                const SizedBox(height: 20),
                const SectionHeader(
                    title: 'Quick Actions',
                    icon: Icons.flash_on,
                    color: MedsColors.purple),
                _quickActions(),
                if (_lastUpdated != null) ...[
                  const SizedBox(height: 18),
                  Center(
                    child: Text(
                      'Last updated ${DateFormat('h:mm a').format(_lastUpdated!)}',
                      style: const TextStyle(
                          color: MedsColors.muted, fontSize: 11.5),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _metrics() {
    final cards = _loading && _data == null
        ? List.generate(4, (_) => const MetricSkeletonCard())
        : _metricCards();
    // IntrinsicHeight rows let each card size to its content (and share the
    // tallest height per row), so nothing overflows on narrow devices.
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth >= 560) {
          return IntrinsicHeight(child: _spacedRow(cards, 12));
        }
        return Column(
          children: [
            IntrinsicHeight(child: _spacedRow(cards.sublist(0, 2), 12)),
            const SizedBox(height: 12),
            IntrinsicHeight(child: _spacedRow(cards.sublist(2, 4), 12)),
          ],
        );
      },
    );
  }

  Widget _spacedRow(List<Widget> children, double gap) {
    final out = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      out.add(Expanded(child: children[i]));
      if (i < children.length - 1) out.add(SizedBox(width: gap));
    }
    return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: out);
  }

  List<Widget> _metricCards() {
    final m = _data?.metrics ?? DashboardMetrics.empty;
    final comparison = _period.comparison;
    return [
      DashboardMetricCard(
        label: 'Total Users',
        value: '${m.totalUsers}',
        icon: Icons.people_alt_outlined,
        color: MedsColors.blue,
        footer: MetricTrendPill(
          percent: m.usersTrend.percent,
          hasBaseline: m.usersTrend.hasBaseline,
          comparison: comparison,
        ),
      ),
      DashboardMetricCard(
        label: 'Active Sessions',
        value: '${m.activeSessions}',
        icon: Icons.desktop_windows_outlined,
        color: MedsColors.purple,
        footer: MetricTrendPill(
          percent: m.sessionsTrend.percent,
          hasBaseline: m.sessionsTrend.hasBaseline,
          comparison: comparison,
        ),
      ),
      DashboardMetricCard(
        label: 'AI Alerts',
        value: '${m.aiAlerts}',
        icon: Icons.shield_outlined,
        color: MedsColors.amber,
        footer: MetricNewPill(count: m.aiAlertsNew, comparison: comparison),
      ),
      DashboardMetricCard(
        label: 'System Health',
        value: '${m.systemHealthPercent}%',
        icon: Icons.favorite_outline,
        color: MedsColors.greenDark,
        footer: SystemStatusIndicator(
          color: _healthColor(m.systemHealthStatus),
          label: m.systemHealthStatus.label,
        ),
      ),
    ];
  }

  Color _healthColor(SystemHealthStatus s) => switch (s) {
        SystemHealthStatus.healthy => MedsColors.greenDark,
        SystemHealthStatus.warning => MedsColors.amber,
        SystemHealthStatus.critical => MedsColors.red,
      };

  Widget _quickActions() {
    final actions = <_QuickAction>[
      _QuickAction(Icons.people_alt_outlined, MedsColors.blue, 'Manage Users',
          () => _openTab(3)),
      _QuickAction(Icons.monitor_heart_outlined, MedsColors.purple,
          'Monitor Sessions', () => _openTab(1)),
      _QuickAction(Icons.description_outlined, MedsColors.amber, 'Reports',
          () => _push(const AdminReportsScreen())),
      _QuickAction(Icons.health_and_safety_outlined, MedsColors.red,
          'System Status', () => _push(const AdminStatusScreen())),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        const cols = 4;
        const spacing = 10.0;
        const targetHeight = 108.0; // icon + two-line label
        final cardWidth = (c.maxWidth - (cols - 1) * spacing) / cols;
        return GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: cardWidth / targetHeight,
          mainAxisSpacing: spacing,
          crossAxisSpacing: spacing,
          children: actions.map((a) => _QuickActionCard(action: a)).toList(),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  final bool refreshing;
  final VoidCallback onRefresh;
  final VoidCallback onNotifications;
  final VoidCallback onSettings;

  const _Header({
    required this.refreshing,
    required this.onRefresh,
    required this.onNotifications,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Dashboard',
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                      color: MedsColors.lightText)),
              SizedBox(height: 4),
              Text('Overview of users, sessions, alerts, and system health',
                  style: TextStyle(color: MedsColors.muted, fontSize: 12.5)),
            ],
          ),
        ),
        const SizedBox(width: 10),
        _HeaderButton(
          icon: Icons.refresh,
          tooltip: 'Refresh',
          color: MedsColors.purple,
          busy: refreshing,
          onTap: refreshing ? null : onRefresh,
        ),
        const SizedBox(width: 8),
        _NotificationButton(onTap: onNotifications),
        const SizedBox(width: 8),
        _HeaderButton(
          icon: Icons.settings_outlined,
          tooltip: 'Settings',
          color: MedsColors.purple,
          onTap: onSettings,
        ),
      ],
    );
  }
}

class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final bool busy;
  final VoidCallback? onTap;

  const _HeaderButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    this.busy = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(13),
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: onTap,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              boxShadow: softShadow(context),
              color: Theme.of(context).colorScheme.surface,
            ),
            child: busy
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: color),
                  )
                : Icon(icon, color: color, size: 21),
          ),
        ),
      ),
    );
  }
}

class _NotificationButton extends StatelessWidget {
  final VoidCallback onTap;

  const _NotificationButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: notifications,
      builder: (context, _) {
        final count = notifications.unreadCount;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            _HeaderButton(
              icon: Icons.notifications_outlined,
              tooltip: 'Notifications',
              color: MedsColors.purple,
              onTap: onTap,
            ),
            if (count > 0)
              Positioned(
                right: -3,
                top: -3,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  constraints:
                      const BoxConstraints(minWidth: 18, minHeight: 18),
                  decoration: BoxDecoration(
                    color: MedsColors.red,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Text(
                    count > 9 ? '9+' : '$count',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        height: 1.2),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Quick actions
// ---------------------------------------------------------------------------

class _QuickAction {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  const _QuickAction(this.icon, this.color, this.label, this.onTap);
}

class _QuickActionCard extends StatelessWidget {
  final _QuickAction action;
  const _QuickActionCard({required this.action});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: action.onTap,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: action.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(action.icon, color: action.color, size: 20),
          ),
          const SizedBox(height: 8),
          Text(
            action.label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, height: 1.15),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Error state
// ---------------------------------------------------------------------------

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
        title: 'Could not load the dashboard',
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
