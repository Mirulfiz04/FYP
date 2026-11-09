import 'package:flutter/material.dart';

import '../../models/user_profile.dart';
import '../../services/admin_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/admin/admin_header.dart';
import '../../widgets/admin/user_badges.dart';
import '../../widgets/admin/user_list_card.dart';
import '../../widgets/admin/user_stat_card.dart';
import '../../widgets/ui_kit.dart';
import '../emotion_analytics_screen.dart';
import 'admin_add_user_screen.dart';
import 'admin_user_detail_screen.dart';

enum _UserTab { all, active, inactive, blocked }

extension _UserTabInfo on _UserTab {
  String get title => switch (this) {
        _UserTab.all => 'All Users',
        _UserTab.active => 'Active',
        _UserTab.inactive => 'Inactive',
        _UserTab.blocked => 'Blocked',
      };
  String? get status => switch (this) {
        _UserTab.all => null,
        _UserTab.active => 'active',
        _UserTab.inactive => 'inactive',
        _UserTab.blocked => 'blocked',
      };
}

/// Admin "Manage Users" — the Users tab of the admin shell. Loads through
/// [AdminUsersSource]; mutations rely on the admin RLS policies. Reachable only
/// from [AdminShell], which is only shown to admins by `RoleRouter`.
class AdminUsersScreen extends StatefulWidget {
  /// Injected in tests; defaults to the real [AdminService].
  final AdminUsersSource? source;

  /// Provided by the shell so the back arrow can return to the dashboard.
  final ValueChanged<int>? onOpenTab;

  const AdminUsersScreen({super.key, this.source, this.onOpenTab});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  late final AdminUsersSource _admin = widget.source ?? AdminService();
  String? _myId;

  static const _pageSize = 8;

  List<UserProfile> _users = [];
  bool _loading = true;
  bool _busy = false;
  Object? _error;

  bool _searchOpen = false;
  String _query = '';
  _UserTab _tab = _UserTab.all;
  String? _roleFilter;
  DateTime? _joinedAfter;
  int _visible = _pageSize;

  @override
  void initState() {
    super.initState();
    try {
      _myId = AuthService().currentUser?.id;
    } catch (_) {
      // Supabase not initialised (e.g. in widget tests) — no "self" guard.
    }
    _load();
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      if (_users.isEmpty) _loading = true;
      _error = null;
    });
    try {
      final users = await _admin.fetchAllUsers();
      if (!mounted) return;
      setState(() => _users = users);
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

  // ---- Derived data -------------------------------------------------------

  int _countStatus(String status) =>
      _users.where((u) => normalizedStatus(u.status) == status).length;

  List<UserProfile> get _filtered {
    final q = _query.trim().toLowerCase();
    return _users.where((u) {
      if (_tab.status != null && normalizedStatus(u.status) != _tab.status) {
        return false;
      }
      if (_roleFilter != null && normalizedRole(u.role) != _roleFilter) {
        return false;
      }
      if (_joinedAfter != null &&
          (u.createdAt == null || u.createdAt!.isBefore(_joinedAfter!))) {
        return false;
      }
      if (q.isNotEmpty) {
        final hay =
            '${u.name ?? ''} ${u.displayName ?? ''} ${u.email ?? ''}'.toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();
  }

  void _resetPaging() => _visible = _pageSize;

  // ---- Actions ------------------------------------------------------------

  void _back() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      widget.onOpenTab?.call(0);
    }
  }

  Future<void> _addUser() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AdminAddUserScreen()),
    );
    if (created == true) {
      _snack('User created successfully', MedsColors.greenDark);
      await _load();
    }
  }

  void _openDetail(UserProfile u) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => AdminUserDetailScreen(user: u)))
        .then((_) {
      if (mounted) _load();
    });
  }

  void _openHistory(UserProfile u) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EmotionAnalyticsScreen(
        userId: u.id,
        title: u.displayLabel,
        subtitle: u.email,
        avatarUrl: u.avatarUrl,
      ),
    ));
  }

  Future<void> _mutate(Future<void> Function() action, String okMessage) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) _snack(okMessage, MedsColors.greenDark);
      await _load();
    } catch (e) {
      if (mounted) _snack('Action failed: $e', MedsColors.red);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeRole(UserProfile u) async {
    const roles = ['user', 'viewer', 'operator', 'researcher', 'admin'];
    final current = normalizedRole(u.role);
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Change role'),
        children: roles
            .map((r) => ListTile(
                  title: Text(roleLabel(r)),
                  trailing: r == current
                      ? const Icon(Icons.check, color: MedsColors.purple)
                      : null,
                  onTap: () => Navigator.pop(ctx, r),
                ))
            .toList(),
      ),
    );
    if (picked != null && picked != normalizedRole(u.role)) {
      await _mutate(() => _admin.setUserRole(u.id, picked),
          '${u.displayLabel} is now ${roleLabel(picked)}');
    }
  }

  Future<void> _editUser(UserProfile u) async {
    final result = await showModalBottomSheet<_EditResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EditUserSheet(user: u),
    );
    if (result == null) return;
    await _mutate(
      () => _admin.updateUser(u.id,
          name: result.name, role: result.role, status: result.status),
      '${result.name} updated successfully',
    );
  }

  Future<void> _toggleActive(UserProfile u) async {
    final activating = normalizedStatus(u.status) != 'active';
    final newStatus = activating ? 'active' : 'inactive';
    await _mutate(() => _admin.setUserStatus(u.id, newStatus),
        '${u.displayLabel} ${activating ? 'activated' : 'deactivated'}');
  }

  Future<void> _toggleBlocked(UserProfile u) async {
    final blocking = !u.isBlocked;
    final ok = await _confirm(
      title: blocking ? 'Block this user?' : 'Unblock this user?',
      message: blocking
          ? 'The user will no longer be able to sign in or start monitoring sessions.'
          : 'The user will be able to sign in and start sessions again.',
      confirmLabel: blocking ? 'Block User' : 'Unblock User',
      danger: blocking,
    );
    if (ok != true) return;
    await _mutate(
      () => _admin.setUserStatus(u.id, blocking ? 'blocked' : 'active'),
      '${u.displayLabel} ${blocking ? 'blocked' : 'unblocked'}',
    );
  }

  Future<void> _deleteUser(UserProfile u) async {
    final ok = await _confirm(
      title: 'Delete this user?',
      message:
          'This removes ${u.displayLabel}\'s profile and data from the system. '
          'This action cannot be undone.',
      confirmLabel: 'Delete User',
      danger: true,
    );
    if (ok != true) return;
    await _mutate(
        () => _admin.deleteUser(u.id), '${u.displayLabel} deleted successfully');
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    bool danger = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: danger
                ? FilledButton.styleFrom(backgroundColor: MedsColors.red)
                : null,
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  void _openMenu(UserProfile u) {
    final isSelf = u.id == _myId;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        Widget item(IconData icon, String label, VoidCallback onTap,
            {Color? color}) {
          return ListTile(
            leading: Icon(icon, color: color),
            title: Text(label, style: color != null ? TextStyle(color: color) : null),
            onTap: () {
              Navigator.pop(ctx);
              onTap();
            },
          );
        }

        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.person_outline,
                      color: MedsColors.purple),
                  title: Text(u.displayLabel,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(u.email ?? '—'),
                ),
              const Divider(height: 1),
              item(Icons.visibility_outlined, 'View User Details',
                  () => _openDetail(u)),
              if (!isSelf)
                item(Icons.edit_outlined, 'Edit User', () => _editUser(u)),
              if (!isSelf)
                item(Icons.badge_outlined, 'Change Role', () => _changeRole(u)),
              item(Icons.insights_outlined, 'View Session History',
                  () => _openHistory(u)),
              if (!isSelf) ...[
                item(
                  normalizedStatus(u.status) == 'active'
                      ? Icons.toggle_off_outlined
                      : Icons.toggle_on_outlined,
                  normalizedStatus(u.status) == 'active'
                      ? 'Deactivate User'
                      : 'Activate User',
                  () => _toggleActive(u),
                ),
                item(
                  u.isBlocked ? Icons.lock_open_outlined : Icons.block,
                  u.isBlocked ? 'Unblock User' : 'Block User',
                  () => _toggleBlocked(u),
                  color: u.isBlocked ? null : MedsColors.red,
                ),
                item(Icons.delete_outline, 'Delete User', () => _deleteUser(u),
                    color: MedsColors.red),
              ],
              if (isSelf)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'You cannot edit, block or delete your own account here.',
                    style: TextStyle(color: MedsColors.muted, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<_FilterResult>(
      context: context,
      showDragHandle: true,
      builder: (_) => _FilterSheet(
        roles: _distinctRoles(),
        role: _roleFilter,
        joinedAfter: _joinedAfter,
      ),
    );
    if (result == null) return;
    setState(() {
      _roleFilter = result.role;
      _joinedAfter = result.joinedAfter;
      _resetPaging();
    });
  }

  List<String> _distinctRoles() {
    final set = <String>{for (final u in _users) normalizedRole(u.role)};
    final ordered = ['admin', 'operator', 'researcher', 'viewer', 'user'];
    return [...ordered.where(set.contains), ...set.where((r) => !ordered.contains(r))];
  }

  void _snack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  // ---- Build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final filterActive = _roleFilter != null || _joinedAfter != null;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(
              onBack: _back,
              onSearch: () => setState(() => _searchOpen = !_searchOpen),
              onAdd: _addUser,
              searchOpen: _searchOpen,
            ),
            if (_searchOpen)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: TextField(
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Search name or email',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (v) => setState(() {
                    _query = v;
                    _resetPaging();
                  }),
                ),
              ),
            Expanded(
              child: _error != null && _users.isEmpty
                  ? _ErrorView(onRetry: _load)
                  : RefreshIndicator(
                      color: MedsColors.purple,
                      onRefresh: _load,
                      child: CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          SliverToBoxAdapter(child: _stats()),
                          SliverToBoxAdapter(child: _tabs(filterActive)),
                          if (_loading && _users.isEmpty)
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

  Widget _stats() {
    final total = _users.length;
    final cards = [
      UserStatCard(
          icon: Icons.groups_outlined,
          color: MedsColors.blue,
          value: '$total',
          label: 'Total Users'),
      UserStatCard(
          icon: Icons.check_circle_outline,
          color: MedsColors.greenDark,
          value: '${_countStatus('active')}',
          label: 'Active Users'),
      UserStatCard(
          icon: Icons.person_off_outlined,
          color: MedsColors.amber,
          value: '${_countStatus('inactive')}',
          label: 'Inactive Users'),
      UserStatCard(
          icon: Icons.shield_outlined,
          color: MedsColors.red,
          value: '${_countStatus('blocked')}',
          label: 'Blocked Users'),
    ];
    return SizedBox(
      height: 142,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        itemCount: cards.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) => cards[i],
      ),
    );
  }

  Widget _tabs(bool filterActive) {
    int countFor(_UserTab t) =>
        t.status == null ? _users.length : _countStatus(t.status!);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _UserTab.values.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final t = _UserTab.values[i];
                  return _TabChip(
                    label: '${t.title} (${countFor(t)})',
                    selected: _tab == t,
                    onTap: () => setState(() {
                      _tab = t;
                      _resetPaging();
                    }),
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          _FilterButton(active: filterActive, onTap: _openFilters),
        ],
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
            icon: Icons.people_outline,
            color: MedsColors.blue,
            title: _users.isEmpty ? 'No users found' : 'No matching users',
            message: _users.isEmpty
                ? 'There are no users in the system yet.'
                : 'No users match the current search or filters.',
            action: (_users.isNotEmpty &&
                    (_query.isNotEmpty || _roleFilter != null || _joinedAfter != null))
                ? OutlinedButton.icon(
                    onPressed: () => setState(() {
                      _query = '';
                      _roleFilter = null;
                      _joinedAfter = null;
                      _tab = _UserTab.all;
                      _searchOpen = false;
                      _resetPaging();
                    }),
                    icon: const Icon(Icons.filter_alt_off_outlined),
                    label: const Text('Clear filters'),
                  )
                : null,
          ),
        ),
      ];
    }

    final shown = _visible.clamp(0, filtered.length);
    final page = filtered.take(shown).toList();
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        sliver: SliverList.builder(
          itemCount: page.length,
          itemBuilder: (context, i) {
            final u = page[i];
            return UserListCard(
              user: u,
              isSelf: u.id == _myId,
              onTap: () => _openDetail(u),
              onMenu: () => _openMenu(u),
            );
          },
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          child: Column(
            children: [
              if (shown < filtered.length)
                OutlinedButton(
                  onPressed: () => setState(
                      () => _visible = (_visible + _pageSize).clamp(0, filtered.length)),
                  child: Text('Load more (${filtered.length - shown} remaining)'),
                ),
              const SizedBox(height: 10),
              Text('Showing 1 to $shown of ${filtered.length} users',
                  style:
                      const TextStyle(color: MedsColors.muted, fontSize: 12.5)),
            ],
          ),
        ),
      ),
    ];
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback onSearch;
  final VoidCallback onAdd;
  final bool searchOpen;

  const _Header({
    required this.onBack,
    required this.onSearch,
    required this.onAdd,
    required this.searchOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 20),
            onPressed: onBack,
            tooltip: 'Back',
          ),
          const Expanded(
            child: Column(
              children: [
                Text('Manage Users',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: MedsColors.lightText)),
                SizedBox(height: 2),
                Text('View and manage system users',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: MedsColors.muted, fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            icon: Icon(searchOpen ? Icons.search_off : Icons.search,
                color: MedsColors.lightText),
            onPressed: onSearch,
            tooltip: 'Search',
          ),
          AdminHeaderButton(
            icon: Icons.add,
            tooltip: 'Add user',
            onTap: onAdd,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab chip + filter button
// ---------------------------------------------------------------------------

class _TabChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabChip(
      {required this.label, required this.selected, required this.onTap});

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
          child: Text(label,
              style: TextStyle(
                  color: selected ? Colors.white : MedsColors.lightText,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
        ),
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;

  const _FilterButton({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Container(
              width: 40,
              height: 38,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: MedsColors.muted.withValues(alpha: 0.25)),
              ),
              child: const Icon(Icons.filter_list,
                  color: MedsColors.purple, size: 20),
            ),
          ),
        ),
        if (active)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: MedsColors.purple,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Error view
// ---------------------------------------------------------------------------

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: EmptyState(
        icon: Icons.cloud_off_outlined,
        color: MedsColors.red,
        title: 'Failed to load users',
        message: 'Something went wrong while loading users.',
        action: FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Try Again'),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filter sheet
// ---------------------------------------------------------------------------

class _FilterResult {
  final String? role;
  final DateTime? joinedAfter;
  const _FilterResult(this.role, this.joinedAfter);
}

class _FilterSheet extends StatefulWidget {
  final List<String> roles;
  final String? role;
  final DateTime? joinedAfter;

  const _FilterSheet({
    required this.roles,
    required this.role,
    required this.joinedAfter,
  });

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  String? _role;
  DateTime? _joinedAfter;

  @override
  void initState() {
    super.initState();
    _role = widget.role;
    _joinedAfter = widget.joinedAfter;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Filters',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            const SizedBox(height: 16),
            const Text('Role', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _choice('Any', _role == null, () => setState(() => _role = null)),
                ...widget.roles.map((r) => _choice(
                    roleLabel(r), _role == r, () => setState(() => _role = r))),
              ],
            ),
            const SizedBox(height: 18),
            const Text('Registered after',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _joinedAfter ?? now,
                  firstDate: DateTime(now.year - 5),
                  lastDate: now,
                );
                if (picked != null) setState(() => _joinedAfter = picked);
              },
              icon: const Icon(Icons.calendar_today_outlined, size: 18),
              label: Text(_joinedAfter == null
                  ? 'Any date'
                  : '${_joinedAfter!.day}/${_joinedAfter!.month}/${_joinedAfter!.year}'),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        Navigator.pop(context, const _FilterResult(null, null)),
                    child: const Text('Clear'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(
                        context, _FilterResult(_role, _joinedAfter)),
                    child: const Text('Apply'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _choice(String label, bool selected, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: MedsColors.purple.withValues(alpha: 0.18),
      labelStyle: TextStyle(
          color: selected ? MedsColors.purple : MedsColors.lightText,
          fontWeight: FontWeight.w600),
    );
  }
}

// ---------------------------------------------------------------------------
// Edit user sheet
// ---------------------------------------------------------------------------

class _EditResult {
  final String name;
  final String role;
  final String status;
  const _EditResult(this.name, this.role, this.status);
}

class _EditUserSheet extends StatefulWidget {
  final UserProfile user;
  const _EditUserSheet({required this.user});

  @override
  State<_EditUserSheet> createState() => _EditUserSheetState();
}

class _EditUserSheetState extends State<_EditUserSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.user.name ?? '');
  late String _role = normalizedRole(widget.user.role);
  late String _status = normalizedStatus(widget.user.status);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Edit user',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Full name'),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _role,
            decoration: const InputDecoration(labelText: 'Role'),
            items: const ['user', 'viewer', 'operator', 'researcher', 'admin']
                .map((r) =>
                    DropdownMenuItem(value: r, child: Text(roleLabel(r))))
                .toList(),
            onChanged: (v) => setState(() => _role = v ?? _role),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _status == 'blocked' ? 'blocked' : _status,
            decoration: const InputDecoration(labelText: 'Account status'),
            items: const ['active', 'inactive', 'blocked']
                .map((s) =>
                    DropdownMenuItem(value: s, child: Text(statusLabel(s))))
                .toList(),
            onChanged: (v) => setState(() => _status = v ?? _status),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                final name = _name.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(context, _EditResult(name, _role, _status));
              },
              child: const Text('Save changes'),
            ),
          ),
        ],
      ),
    );
  }
}
