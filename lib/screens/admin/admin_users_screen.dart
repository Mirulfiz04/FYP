import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/user_profile.dart';
import '../../services/admin_service.dart';
import '../../services/auth_service.dart';
import '../emotion_analytics_screen.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final _admin = AdminService();
  final _myId = AuthService().currentUser?.id;

  List<UserProfile> _users = [];
  String _query = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final users = await _admin.fetchAllUsers();
      if (mounted) {
        setState(() {
          _users = users;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _snack('Could not load users: $e', error: true);
      }
    }
  }

  List<UserProfile> get _filtered {
    if (_query.isEmpty) return _users;
    final q = _query.toLowerCase();
    return _users.where((u) {
      return (u.name ?? '').toLowerCase().contains(q) ||
          (u.email ?? '').toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _toggleRole(UserProfile u) async {
    final newRole = u.isAdmin ? 'user' : 'admin';
    try {
      await _admin.setUserRole(u.id, newRole);
      _snack('${u.email ?? 'User'} is now $newRole');
      await _load();
    } catch (e) {
      _snack('Failed: $e', error: true);
    }
  }

  Future<void> _toggleBlocked(UserProfile u) async {
    final newStatus = u.isBlocked ? 'active' : 'blocked';
    try {
      await _admin.setUserStatus(u.id, newStatus);
      _snack('${u.email ?? 'User'} ${newStatus == 'blocked' ? 'blocked' : 'unblocked'}');
      await _load();
    } catch (e) {
      _snack('Failed: $e', error: true);
    }
  }

  void _openUser(UserProfile u) {
    final isSelf = u.id == _myId;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(u.name?.isNotEmpty == true ? u.name! : '(no name)',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  Text(u.email ?? '—',
                      style: const TextStyle(color: Colors.grey)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 16,
                    runSpacing: 4,
                    children: [
                      _meta('Role', u.role ?? 'user'),
                      _meta('Status', u.status ?? 'active'),
                      _meta('Age', u.age?.toString() ?? '—'),
                      _meta('Gender', u.gender ?? '—'),
                      _meta('Contact', u.contactNumber ?? '—'),
                      _meta('Location', u.location ?? '—'),
                      if (u.createdAt != null)
                        _meta('Joined',
                            DateFormat('dd MMM yyyy').format(u.createdAt!)),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.insights_outlined,
                  color: Color(0xFF9B30FF)),
              title: const Text('View emotion analytics'),
              subtitle: const Text('Emotions & heart-rate for this user'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => EmotionAnalyticsScreen(
                      userId: u.id,
                      title: u.name?.isNotEmpty == true
                          ? u.name!
                          : (u.email ?? 'User'),
                      subtitle: u.email,
                      avatarUrl: u.avatarUrl,
                    ),
                  ),
                );
              },
            ),
            const Divider(height: 1),
            if (isSelf)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'You cannot change the role or status of your own account.',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              )
            else ...[
              ListTile(
                leading: Icon(u.isAdmin
                    ? Icons.person_outline
                    : Icons.admin_panel_settings_outlined),
                title: Text(u.isAdmin ? 'Demote to user' : 'Promote to admin'),
                onTap: () {
                  Navigator.pop(ctx);
                  _toggleRole(u);
                },
              ),
              ListTile(
                leading: Icon(u.isBlocked ? Icons.lock_open : Icons.block,
                    color: u.isBlocked ? null : Colors.red.shade400),
                title: Text(u.isBlocked ? 'Unblock account' : 'Block account',
                    style: u.isBlocked
                        ? null
                        : TextStyle(color: Colors.red.shade400)),
                onTap: () {
                  Navigator.pop(ctx);
                  _toggleBlocked(u);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _meta(String label, String value) {
    return Text.rich(TextSpan(children: [
      TextSpan(
          text: '$label: ',
          style: const TextStyle(color: Colors.grey, fontSize: 12)),
      TextSpan(
          text: value,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    ]));
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red.shade700 : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Manage Users  (${_users.length})'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search name or email',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF00DC64)))
                : _filtered.isEmpty
                    ? const Center(
                        child: Text('No users found',
                            style: TextStyle(color: Colors.grey)))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          itemCount: _filtered.length,
                          separatorBuilder: (_, __) => Divider(
                              height: 1,
                              color: Theme.of(context).dividerColor),
                          itemBuilder: (context, i) {
                            final u = _filtered[i];
                            return _UserTile(
                              user: u,
                              isSelf: u.id == _myId,
                              onTap: () => _openUser(u),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  final UserProfile user;
  final bool isSelf;
  final VoidCallback onTap;

  const _UserTile({
    required this.user,
    required this.isSelf,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final blocked = user.isBlocked;
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: const Color(0xFF00DC64).withValues(alpha: 0.15),
        backgroundImage: (user.avatarUrl != null && user.avatarUrl!.isNotEmpty)
            ? NetworkImage(user.avatarUrl!)
            : null,
        child: (user.avatarUrl == null || user.avatarUrl!.isEmpty)
            ? const Icon(Icons.person, color: Color(0xFF00DC64))
            : null,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(user.name?.isNotEmpty == true ? user.name! : '(no name)',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          if (isSelf)
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Text('you',
                  style: TextStyle(color: Colors.grey, fontSize: 11)),
            ),
        ],
      ),
      subtitle: Text(user.email ?? '—',
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (user.isAdmin)
            _badge('ADMIN', const Color(0xFF00B4FF)),
          if (blocked) ...[
            const SizedBox(width: 6),
            _badge('BLOCKED', const Color(0xFFFF5050)),
          ],
        ],
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontWeight: FontWeight.bold, fontSize: 10)),
    );
  }
}
