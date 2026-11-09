import 'package:flutter/material.dart';

import '../../models/admin_sessions_model.dart';
import '../../services/admin_sessions_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/admin/admin_header.dart';
import '../../widgets/admin/admin_tab_chip.dart';
import '../../widgets/admin/dashboard_metric_card.dart';
import '../../widgets/admin/monitor_session_card.dart';
import '../../widgets/ui_kit.dart';
import 'admin_session_detail_screen.dart';

enum _SessionTab { all, live, completed, flagged }

extension _SessionTabInfo on _SessionTab {
  String get title => switch (this) {
        _SessionTab.all => 'All',
        _SessionTab.live => 'Live',
        _SessionTab.completed => 'Completed',
        _SessionTab.flagged => 'Flagged',
      };
  ActivityStatus? get status => switch (this) {
        _SessionTab.all => null,
        _SessionTab.live => ActivityStatus.live,
        _SessionTab.completed => ActivityStatus.completed,
        _SessionTab.flagged => ActivityStatus.flagged,
      };
}

/// Admin "Monitor Sessions" — the Sessions tab of the admin shell. Loads
/// through [AdminSessionsSource]; no Supabase calls live in the widgets.
class AdminSessionsScreen extends StatefulWidget {
  /// Injected in tests; defaults to the real service.
  final AdminSessionsSource? source;

  /// Provided by the shell so the back arrow can return to the dashboard.
  final ValueChanged<int>? onOpenTab;

  const AdminSessionsScreen({super.key, this.source, this.onOpenTab});

  @override
  State<AdminSessionsScreen> createState() => _AdminSessionsScreenState();
}

class _AdminSessionsScreenState extends State<AdminSessionsScreen> {
  late final AdminSessionsSource _source =
      widget.source ?? AdminSessionsService();
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  MonitorSessionsData? _data;
  bool _loading = true;
  bool _busy = false;
  Object? _error;
  _SessionTab _tab = _SessionTab.all;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      if (_data == null) _loading = true;
      _error = null;
    });
    try {
      final data = await _source.fetchSessions();
      if (!mounted) return;
      setState(() => _data = data);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _busy = false;
        });
      }
    }
  }

  List<MonitorSession> get _filtered {
    final d = _data;
    if (d == null) return const [];
    return d.sessions.where((s) {
      if (_tab.status != null && s.status != _tab.status) return false;
      return s.matches(_query.trim());
    }).toList();
  }

  void _back() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      widget.onOpenTab?.call(0);
    }
  }

  void _open(MonitorSession s) {
    Navigator.of(context)
        .push(MaterialPageRoute(
            builder: (_) => AdminSessionDetailScreen(
                  session: s.session,
                  userName: s.userName,
                  avatarUrl: s.avatarUrl,
                  initials: s.initials,
                )))
        .then((_) {
      if (mounted) _load();
    });
  }

  Future<void> _openFilter() async {
    final picked = await showModalBottomSheet<_SessionTab>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Filter by status',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
            ..._SessionTab.values.map((t) => ListTile(
                  leading: Icon(
                    t == _SessionTab.all ? Icons.list_alt : Icons.circle,
                    size: t == _SessionTab.all ? 22 : 12,
                    color: t.status == null
                        ? MedsColors.muted
                        : sessionStatusColor(t.status!),
                  ),
                  title: Text(t == _SessionTab.all ? 'All sessions' : t.title),
                  trailing: _tab == t
                      ? const Icon(Icons.check, color: MedsColors.purple)
                      : null,
                  onTap: () => Navigator.pop(ctx, t),
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _tab = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(),
            Expanded(
              child: _error != null && _data == null
                  ? _ErrorView(onRetry: _load)
                  : RefreshIndicator(
                      color: MedsColors.purple,
                      onRefresh: _load,
                      child: CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          SliverToBoxAdapter(child: _stats()),
                          SliverToBoxAdapter(child: _tabs()),
                          SliverToBoxAdapter(child: _searchBar()),
                          if (_loading && _data == null)
                            const SliverFillRemaining(
                              hasScrollBody: false,
                              child: Center(
                                  child: CircularProgressIndicator(
                                      color: MedsColors.purple)),
                            )
                          else
                            ..._listSlivers(),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 20),
            onPressed: _back,
            tooltip: 'Back',
          ),
          const Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Monitor Sessions',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          height: 1.1,
                          color: MedsColors.lightText)),
                  SizedBox(height: 2),
                  Text('Track all user monitoring sessions',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: MedsColors.muted, fontSize: 12.5)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          AdminHeaderButton(
            icon: Icons.search,
            tooltip: 'Search',
            onTap: () => _searchFocus.requestFocus(),
          ),
          const SizedBox(width: 8),
          AdminHeaderButton(
            icon: Icons.filter_list,
            tooltip: 'Filter',
            onTap: _openFilter,
          ),
        ],
      ),
    );
  }

  Widget _stats() {
    final d = _data ?? MonitorSessionsData.empty;
    const comparison = 'vs last 7d';
    final cards = <Widget>[
      _StatBox(
        child: DashboardMetricCard(
          label: 'Total Sessions',
          value: '${d.total}',
          icon: Icons.show_chart,
          color: MedsColors.purple,
          footer: MetricTrendPill(
              percent: d.totalDeltaPct, hasBaseline: true, comparison: comparison),
        ),
      ),
      _StatBox(
        child: DashboardMetricCard(
          label: 'Live Sessions',
          value: '${d.live}',
          icon: Icons.sensors,
          color: MedsColors.greenDark,
          footer: MetricTrendPill(
              percent: d.liveDeltaPct, hasBaseline: true, comparison: comparison),
        ),
      ),
      _StatBox(
        child: DashboardMetricCard(
          label: 'Completed',
          value: '${d.completed}',
          icon: Icons.check_circle_outline,
          color: MedsColors.blue,
          footer: MetricTrendPill(
              percent: d.completedDeltaPct,
              hasBaseline: true,
              comparison: comparison),
        ),
      ),
      _StatBox(
        child: DashboardMetricCard(
          label: 'Flagged',
          value: '${d.flagged}',
          icon: Icons.flag_outlined,
          color: MedsColors.amber,
          footer: MetricNewPill(count: d.flaggedDelta, comparison: comparison),
        ),
      ),
    ];
    return SizedBox(
      height: 150,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        itemCount: cards.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) => cards[i],
      ),
    );
  }

  Widget _tabs() {
    final d = _data ?? MonitorSessionsData.empty;
    int countFor(_SessionTab t) => switch (t) {
          _SessionTab.all => d.total,
          _SessionTab.live => d.live,
          _SessionTab.completed => d.completed,
          _SessionTab.flagged => d.flagged,
        };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: SizedBox(
        height: 38,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _SessionTab.values.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final t = _SessionTab.values[i];
            return AdminTabChip(
              label: '${t.title} (${countFor(t)})',
              selected: _tab == t,
              onTap: () => setState(() => _tab = t),
            );
          },
        ),
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocus,
        decoration: const InputDecoration(
          hintText: 'Search by user name, email or session ID',
          prefixIcon: Icon(Icons.search),
        ),
        onChanged: (v) => setState(() => _query = v),
      ),
    );
  }

  List<Widget> _listSlivers() {
    final filtered = _filtered;
    if (filtered.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: Icons.event_busy_outlined,
            color: MedsColors.blue,
            title: (_data?.sessions.isEmpty ?? true)
                ? 'No sessions yet'
                : 'No matching sessions',
            message: (_data?.sessions.isEmpty ?? true)
                ? 'Detection sessions across users will show here.'
                : 'No sessions match this filter or search.',
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        sliver: SliverList.builder(
          itemCount: filtered.length,
          itemBuilder: (context, i) =>
              MonitorSessionCard(item: filtered[i], onOpen: () => _open(filtered[i])),
        ),
      ),
    ];
  }
}

/// Fixed-width wrapper so the metric cards scroll horizontally without
/// overflowing on narrow phones.
class _StatBox extends StatelessWidget {
  final Widget child;
  const _StatBox({required this.child});

  @override
  Widget build(BuildContext context) => SizedBox(width: 156, child: child);
}

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: EmptyState(
        icon: Icons.cloud_off_outlined,
        color: MedsColors.red,
        title: 'Failed to load sessions',
        message: 'Something went wrong while loading sessions.',
        action: FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Try Again'),
        ),
      ),
    );
  }
}
