import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/data_export_service.dart';
import '../services/session_repository.dart';
import '../theme/app_theme.dart';
import '../viewmodels/history_view_model.dart';
import '../widgets/app_nav_drawer.dart';
import '../widgets/email_export_sheet.dart';
import '../widgets/history_filter_sheet.dart';
import '../widgets/history_summary_card.dart';
import '../widgets/notification_bell.dart';
import '../widgets/session_history_card.dart';
import '../widgets/ui_kit.dart';
import 'notifications_screen.dart';
import 'session_details_page.dart';
import 'session_readiness_screen.dart';

const Color _accent = Color(0xFF6A5AE0);

/// The Session History tab. Thin UI over [HistoryViewModel] — all data,
/// filtering and search live in the view model + repository.
class HistoryScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  final ValueChanged<int> onOpenTab;

  const HistoryScreen({
    super.key,
    required this.cameras,
    required this.onOpenTab,
  });

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _vm = HistoryViewModel(repository: SupabaseSessionRepository());
  final _auth = AuthService();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  String? _name;
  String? _avatarUrl;

  // Multi-select bulk export.
  bool _selecting = false;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _vm.load();
    _loadProfile();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
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

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 240) {
      _vm.loadMore();
    }
  }

  // --- Multi-select --------------------------------------------------------

  void _enterSelection(String firstId) {
    setState(() {
      _selecting = true;
      _selected
        ..clear()
        ..add(firstId);
    });
  }

  void _exitSelection() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (!_selected.add(id)) _selected.remove(id);
      if (_selected.isEmpty) _selecting = false;
    });
  }

  void _selectAllVisible() {
    setState(() {
      _selected.addAll(_vm.visible.map((s) => s.sessionId));
    });
  }

  Future<void> _exportSelected() async {
    if (_selected.isEmpty) return;
    final ids = Set<String>.from(_selected);
    final myEmail = _auth.currentUser?.email;
    final sent = await showEmailExportSheet(
      context,
      title: 'Export ${ids.length} session${ids.length == 1 ? '' : 's'}',
      subject: 'MEDS — ${ids.length} session${ids.length == 1 ? '' : 's'}',
      myEmail: myEmail,
      historyScope: 'multi',
      builder: ({required bool includeCsv, required bool includePdf}) =>
          DataExportService().loadSelectedExport(
        sessionIds: ids,
        includeCsv: includeCsv,
        includePdf: includePdf,
      ),
    );
    if (sent && mounted) _exitSelection();
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
    );
    if (range != null) {
      _vm.setDateFilter(DateFilter.custom, start: range.start, end: range.end);
    }
  }

  Future<void> _openFilters() async {
    final result = await showHistoryFilterSheet(context, _vm.filters);
    if (result != null) _vm.setFilters(result);
  }

  void _openSummary(String sessionId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SessionDetailsPage(sessionId: sessionId),
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && mounted) _exitSelection();
      },
      child: Scaffold(
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
                      _selecting ? _selectionHeader() : _header(),
                      const SizedBox(height: 16),
                      if (!_selecting) ...[
                        _filterChips(),
                        const SizedBox(height: 12),
                        _searchBar(),
                        const SizedBox(height: 12),
                      ],
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
                if (_selecting) _selectionBar(),
              ],
            );
          },
        ),
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
              Text('History',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              SizedBox(height: 2),
              Text('Review your past emotional monitoring sessions.',
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
          child: IconButton(
            icon: const Icon(Icons.checklist_rounded, color: _accent),
            tooltip: 'Select & export',
            onPressed: _vm.hasAnySessions
                ? () => setState(() {
                      _selecting = true;
                      _selected.clear();
                    })
                : null,
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

  Widget _selectionHeader() {
    return Row(
      children: [
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            boxShadow: softShadow(context),
          ),
          child: IconButton(
            icon: const Icon(Icons.close, color: _accent),
            tooltip: 'Cancel',
            onPressed: _exitSelection,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text('${_selected.length} selected',
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ),
        TextButton.icon(
          onPressed: _selectAllVisible,
          icon: const Icon(Icons.done_all, size: 18),
          label: const Text('Select all'),
          style: TextButton.styleFrom(foregroundColor: _accent),
        ),
      ],
    );
  }

  Widget _selectionBar() {
    final n = _selected.length;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  n == 0 ? 'Tap sessions to select them' : '$n selected',
                  style: TextStyle(
                    color: n == 0 ? MedsColors.muted : null,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: n == 0 ? null : _exportSelected,
                style: FilledButton.styleFrom(
                    backgroundColor: MedsColors.greenDark),
                icon: const Icon(Icons.mark_email_read_outlined),
                label: Text('Export${n == 0 ? '' : ' ($n)'}'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterChips() {
    const labels = {
      DateFilter.today: 'Today',
      DateFilter.week: 'This Week',
      DateFilter.month: 'This Month',
      DateFilter.custom: 'Custom',
    };
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: labels.entries.map((e) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _chip(
                    label: e.value,
                    selected: _vm.dateFilter == e.key,
                    onTap: () {
                      if (e.key == DateFilter.custom) {
                        _pickCustomRange();
                      } else {
                        _vm.setDateFilter(e.key);
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _FilterButton(
          activeCount: _vm.filters.activeCount,
          onTap: _openFilters,
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
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: selected
                ? null
                : Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : MedsColors.muted,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _searchBar() {
    return TextField(
      controller: _searchCtrl,
      onChanged: _vm.setSearch,
      decoration: InputDecoration(
        hintText: 'Search session or date',
        prefixIcon: const Icon(Icons.search, color: MedsColors.muted),
        suffixIcon: _searchCtrl.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  _searchCtrl.clear();
                  _vm.setSearch('');
                },
              ),
      ),
    );
  }

  Widget _content() {
    if (_vm.loading && !_vm.hasAnySessions) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(
            height: 320,
            child: Center(child: CircularProgressIndicator(color: _accent)),
          ),
        ],
      );
    }

    if (_vm.error != null) {
      return _stateScroll(
        EmptyState(
          icon: Icons.cloud_off,
          title: 'Session history could not be loaded.',
          message: 'Please check your connection and try again.',
          color: MedsColors.red,
          action: FilledButton.icon(
            onPressed: _vm.refresh,
            style: FilledButton.styleFrom(backgroundColor: _accent),
            icon: const Icon(Icons.refresh),
            label: const Text('Try Again'),
          ),
        ),
      );
    }

    if (!_vm.hasAnySessions) {
      return _stateScroll(
        EmptyState(
          icon: Icons.event_busy,
          title: 'No monitoring sessions found',
          message:
              'Complete your first monitoring session to view your emotional '
              'history here.',
          color: MedsColors.purple,
          action: FilledButton.icon(
            onPressed: _startSession,
            style: FilledButton.styleFrom(backgroundColor: _accent),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start New Session'),
          ),
        ),
      );
    }

    final items = _vm.visible;
    if (items.isEmpty) {
      return _stateScroll(
        EmptyState(
          icon: Icons.filter_alt_off,
          title: 'No sessions match the selected filters.',
          message: 'Try a different date range or clear your filters.',
          color: MedsColors.blue,
          action: OutlinedButton.icon(
            onPressed: () {
              _searchCtrl.clear();
              _vm.clearFilters();
            },
            icon: const Icon(Icons.filter_alt_off),
            label: const Text('Clear filters'),
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollCtrl,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: items.length + 2, // summary header + items + footer
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: HistorySummaryCard(summary: _vm.summary),
          );
        }
        if (i == items.length + 1) {
          return _vm.hasMore
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                      child: SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: _accent))),
                )
              : const SizedBox(height: 8);
        }
        final s = items[i - 1];
        return SessionHistoryCard(
          session: s,
          onViewSummary: () => _openSummary(s.sessionId),
          selectionMode: _selecting,
          selected: _selected.contains(s.sessionId),
          onSelectToggle: () => _toggleSelection(s.sessionId),
          onLongPress: () => _enterSelection(s.sessionId),
        );
      },
    );
  }

  Widget _stateScroll(Widget child) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [SizedBox(height: 360, child: child)],
    );
  }
}

class _FilterButton extends StatelessWidget {
  final int activeCount;
  final VoidCallback onTap;
  const _FilterButton({required this.activeCount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: IconButton(
            icon: const Icon(Icons.tune, color: _accent),
            tooltip: 'More filters',
            onPressed: onTap,
          ),
        ),
        if (activeCount > 0)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              width: 18,
              height: 18,
              decoration: const BoxDecoration(
                  color: MedsColors.red, shape: BoxShape.circle),
              child: Center(
                child: Text('$activeCount',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
              ),
            ),
          ),
      ],
    );
  }
}
