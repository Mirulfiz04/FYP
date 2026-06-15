import 'package:flutter/material.dart';
import '../../services/admin_service.dart';
import '../../services/auth_service.dart';
import '../settings_screen.dart';
import 'admin_analytics_screen.dart';
import 'admin_reports_screen.dart';
import 'admin_sessions_screen.dart';
import 'admin_status_screen.dart';
import 'admin_users_screen.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  final _admin = AdminService();
  final _auth = AuthService();
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
      // Stats are best-effort on the landing screen.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirmSignOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sign out')),
        ],
      ),
    );
    if (ok == true) await _auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final s = _stats;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Panel'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'My profile & theme',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: _confirmSignOut,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Overview',
              style: TextStyle(
                color: Colors.grey,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 10),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                    child: CircularProgressIndicator(color: Color(0xFF00DC64))),
              )
            else
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.7,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                children: [
                  _StatCard(
                      label: 'Users',
                      value: '${s?.totalUsers ?? '—'}',
                      icon: Icons.people_outline,
                      color: const Color(0xFF00B4FF)),
                  _StatCard(
                      label: 'Sessions',
                      value: '${s?.totalSessions ?? '—'}',
                      icon: Icons.event_note_outlined,
                      color: const Color(0xFF9B30FF)),
                  _StatCard(
                      label: 'Active now',
                      value: '${s?.activeSessions ?? '—'}',
                      icon: Icons.sensors,
                      color: const Color(0xFF00DC64)),
                  _StatCard(
                      label: 'Readings',
                      value: '${s?.totalReadings ?? '—'}',
                      icon: Icons.insights_outlined,
                      color: const Color(0xFFFFA500)),
                ],
              ),
            const SizedBox(height: 24),
            const Text(
              'MANAGEMENT',
              style: TextStyle(
                color: Colors.grey,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 20),
            _FeatureTile(
              icon: Icons.manage_accounts_outlined,
              color: const Color(0xFF00B4FF),
              title: 'Manage users',
              subtitle: 'View users, change roles, block / unblock',
              onTap: () => _push(const AdminUsersScreen()),
            ),
            _FeatureTile(
              icon: Icons.monitor_heart_outlined,
              color: const Color(0xFF9B30FF),
              title: 'Monitor sessions',
              subtitle: 'All detection sessions across users',
              onTap: () => _push(const AdminSessionsScreen()),
            ),
            _FeatureTile(
              icon: Icons.analytics_outlined,
              color: const Color(0xFF00DC64),
              title: 'Analytics dashboard',
              subtitle: 'Usage, emotions and session metrics',
              onTap: () => _push(const AdminAnalyticsScreen()),
            ),
            _FeatureTile(
              icon: Icons.description_outlined,
              color: const Color(0xFFFFA500),
              title: 'Generate reports',
              subtitle: 'Summary and CSV you can copy / export',
              onTap: () => _push(const AdminReportsScreen()),
            ),
            _FeatureTile(
              icon: Icons.health_and_safety_outlined,
              color: const Color(0xFFFF5050),
              title: 'System status',
              subtitle: 'Database, auth, storage and sensor health',
              onTap: () => _push(const AdminStatusScreen()),
            ),
          ],
        ),
      ),
    );
  }

  void _push(Widget screen) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => screen))
        .then((_) => _load());
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(value,
              style:
                  const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _FeatureTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle,
            style: const TextStyle(color: Colors.grey, fontSize: 12)),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      ),
    );
  }
}
