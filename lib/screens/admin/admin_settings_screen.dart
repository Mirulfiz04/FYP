import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/user_profile.dart';
import '../../services/ai_config.dart';
import '../../services/auth_service.dart';
import '../../services/notification_service.dart';
import '../../services/profile_repository.dart';
import '../../theme/app_theme.dart';
import '../../viewmodels/profile_view_model.dart';
import '../../widgets/admin/setting_row.dart';
import '../../widgets/ui_kit.dart';
import '../appearance_screen.dart';
import '../edit_profile_screen.dart';
import '../notification_settings_screen.dart';
import '../notifications_screen.dart';
import '../privacy_security_screen.dart';
import 'admin_info_screen.dart';
import 'admin_status_screen.dart';

const String _twoFaPrefKey = 'admin_2fa_enabled';

/// Admin Settings — the Settings tab of the admin shell. Account / System /
/// Security / System Health groups plus a sign-out row. Reachable only via
/// [AdminShell], which `RoleRouter` shows to admins only; RBAC-sensitive rows
/// additionally check the loaded profile's role.
class AdminSettingsScreen extends StatefulWidget {
  final ValueChanged<int>? onOpenTab;

  /// Injected in tests; default to the real services.
  final Future<UserProfile?> Function()? profileLoader;
  final Future<void> Function()? onSignOut;

  const AdminSettingsScreen({
    super.key,
    this.onOpenTab,
    this.profileLoader,
    this.onSignOut,
  });

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  UserProfile? _profile;
  bool _loading = true;
  bool _twoFa = true;
  Object? _error;

  bool get _isAdmin => _profile?.isAdmin ?? false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final loader =
          widget.profileLoader ?? () => AuthService().loadProfile();
      final profile = await loader();
      bool twoFa = true;
      try {
        final prefs = await SharedPreferences.getInstance();
        twoFa = prefs.getBool(_twoFaPrefKey) ?? true;
      } catch (_) {/* prefs unavailable */}
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _twoFa = twoFa;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _push(Widget screen) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => screen))
        .then((_) {
      if (mounted) _load(); // refresh badges (e.g. 2FA) on return
    });
  }

  /// Guards RBAC-sensitive destinations. The screen is already admin-only, but
  /// this is a defensive second check.
  void _adminOnly(Widget screen) {
    if (!_isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('This section is restricted to administrators.')));
      return;
    }
    _push(screen);
  }

  void _openProfile() {
    final vm = ProfileViewModel(repository: SupabaseProfileRepository());
    vm.load();
    _push(EditProfileScreen(vm: vm));
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out of Admin Panel?'),
        content: const Text(
            'You will need to sign in again to access administrator features.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: MedsColors.red),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final signOut = widget.onSignOut ?? () => AuthService().signOut();
      await signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: _error != null && _profile == null
            ? _ErrorView(onRetry: _load)
            : RefreshIndicator(
                color: MedsColors.purple,
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  children: [
                    _header(),
                    const SizedBox(height: 18),
                    if (_loading && _profile == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 60),
                        child: Center(
                            child: CircularProgressIndicator(
                                color: MedsColors.purple)),
                      )
                    else ...[
                      ..._account(),
                      const SizedBox(height: 18),
                      ..._system(),
                      const SizedBox(height: 18),
                      ..._security(),
                      const SizedBox(height: 18),
                      ..._systemHealth(),
                      const SizedBox(height: 18),
                      _logout(),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  // ---- Header -------------------------------------------------------------

  Widget _header() {
    final hasPhoto =
        _profile?.avatarUrl != null && _profile!.avatarUrl!.isNotEmpty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Admin Settings',
                  style: TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                      color: MedsColors.lightText)),
              SizedBox(height: 4),
              Text('Manage your account and system preferences',
                  style: TextStyle(color: MedsColors.muted, fontSize: 12.5)),
            ],
          ),
        ),
        const SizedBox(width: 10),
        _BellButton(onTap: () => _push(const NotificationsScreen())),
        const SizedBox(width: 8),
        InkWell(
          onTap: _openProfile,
          customBorder: const CircleBorder(),
          child: CircleAvatar(
            radius: 22,
            backgroundColor: MedsColors.purple.withValues(alpha: 0.15),
            backgroundImage:
                hasPhoto ? NetworkImage(_profile!.avatarUrl!) : null,
            child: hasPhoto
                ? null
                : Text(_profile?.initials ?? 'A',
                    style: const TextStyle(
                        color: MedsColors.purple,
                        fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  // ---- Sections -----------------------------------------------------------

  List<Widget> _account() {
    return [
      const SectionHeader(
          title: 'Account', icon: Icons.person, color: MedsColors.purple),
      SettingsGroupCard(children: [
        SettingRow(
          icon: Icons.account_circle_outlined,
          color: MedsColors.purple,
          title: 'Profile Information',
          subtitle: 'Update your personal information',
          onTap: _openProfile,
        ),
        SettingRow(
          icon: Icons.lock_outline,
          color: MedsColors.purple,
          title: 'Change Password',
          subtitle: 'Update your account password',
          onTap: () => _push(const PrivacySecurityScreen()),
        ),
        SettingRow(
          icon: Icons.verified_user_outlined,
          color: MedsColors.purple,
          title: 'Two-Factor Authentication',
          subtitle: 'Manage additional account security',
          trailing: SettingBadge(
            text: _twoFa ? 'Enabled' : 'Disabled',
            color: _twoFa ? MedsColors.greenDark : MedsColors.muted,
          ),
          onTap: () => _push(const AdminInfoScreen(
            title: 'Two-Factor Authentication',
            subtitle: 'Add a second step when signing in.',
            icon: Icons.verified_user_outlined,
            color: MedsColors.purple,
            togglePrefKey: _twoFaPrefKey,
            toggleTitle: 'Two-factor authentication',
            toggleSubtitle: 'Require a verification step at sign-in.',
            toggleDefault: true,
            bullets: [
              'Protects the admin panel if a password is leaked.',
              'Applies to administrator accounts on this device.',
            ],
          )),
        ),
      ]),
    ];
  }

  List<Widget> _system() {
    return [
      const SectionHeader(
          title: 'System', icon: Icons.settings, color: MedsColors.blue),
      SettingsGroupCard(children: [
        SettingRow(
          icon: Icons.tune,
          color: MedsColors.blue,
          title: 'General Settings',
          subtitle: 'Configure system preferences',
          onTap: () => _push(const AppearanceScreen()),
        ),
        SettingRow(
          icon: Icons.notifications_outlined,
          color: MedsColors.blue,
          title: 'Notifications',
          subtitle: 'Manage notification preferences',
          onTap: () => _push(const NotificationSettingsScreen()),
        ),
        SettingRow(
          icon: Icons.storage_outlined,
          color: MedsColors.blue,
          title: 'Data Retention',
          subtitle: 'Manage data storage and retention policies',
          onTap: () => _adminOnly(const AdminInfoScreen(
            title: 'Data Retention',
            subtitle: 'Control how long session data is kept.',
            icon: Icons.storage_outlined,
            color: MedsColors.blue,
            bullets: [
              'Session readings and summaries are retained for analytics.',
              'Users can delete their own history from Privacy & Security.',
              'Configurable retention windows are part of the admin roadmap.',
            ],
          )),
        ),
      ]),
    ];
  }

  List<Widget> _security() {
    return [
      const SectionHeader(
          title: 'Security',
          icon: Icons.shield_outlined,
          color: MedsColors.greenDark),
      SettingsGroupCard(children: [
        SettingRow(
          icon: Icons.groups_outlined,
          color: MedsColors.greenDark,
          title: 'Access Control',
          subtitle: 'Manage administrator roles and permissions',
          onTap: () {
            if (!_isAdmin) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Restricted to administrators.')));
              return;
            }
            widget.onOpenTab?.call(3); // Users tab manages roles
          },
        ),
        SettingRow(
          icon: Icons.desktop_windows_outlined,
          color: MedsColors.greenDark,
          title: 'Login Sessions',
          subtitle: 'View active administrator sessions',
          onTap: () => _push(AdminInfoScreen(
            title: 'Login Sessions',
            subtitle: 'Your active administrator session.',
            icon: Icons.desktop_windows_outlined,
            color: MedsColors.greenDark,
            bullets: [
              'Signed in as ${_profile?.email ?? 'this account'}.',
              'Sign out of every device if you suspect unauthorised access.',
            ],
            actionLabel: 'Sign out all devices',
            actionIcon: Icons.logout,
            actionDanger: true,
            onAction: () => AuthService().signOutEverywhere(),
          )),
        ),
        SettingRow(
          icon: Icons.receipt_long_outlined,
          color: MedsColors.greenDark,
          title: 'Audit Logs',
          subtitle: 'Review administrator and system activities',
          onTap: () => _adminOnly(const AdminInfoScreen(
            title: 'Audit Logs',
            subtitle: 'A record of administrator and system activity.',
            icon: Icons.receipt_long_outlined,
            color: MedsColors.greenDark,
            bullets: [
              'Tracks role changes, blocks, exports and sign-outs.',
              'Persisted audit logging requires the admin audit table.',
            ],
          )),
        ),
      ]),
    ];
  }

  List<Widget> _systemHealth() {
    return [
      const SectionHeader(
          title: 'System Health',
          icon: Icons.monitor_heart_outlined,
          color: MedsColors.amber),
      SettingsGroupCard(children: [
        SettingRow(
          icon: Icons.health_and_safety_outlined,
          color: MedsColors.amber,
          title: 'System Status',
          subtitle: 'Check database, authentication, storage and service status',
          onTap: () => _push(const AdminStatusScreen()),
        ),
        SettingRow(
          icon: Icons.extension_outlined,
          color: MedsColors.amber,
          title: 'Integrations',
          subtitle: 'Manage AI API and external service integrations',
          onTap: () => _adminOnly(const AdminInfoScreen(
            title: 'Integrations',
            subtitle: 'AI and external service connections.',
            icon: Icons.extension_outlined,
            color: MedsColors.amber,
            bullets: [
              'AI provider: Anthropic Claude',
              'Connection: Supabase Edge Function "${AiConfig.functionName}"',
              'API key: Supabase secret ANTHROPIC_API_KEY (never in the app)',
              'Supabase: authentication, database and storage',
            ],
          )),
        ),
        SettingRow(
          icon: Icons.cloud_upload_outlined,
          color: MedsColors.amber,
          title: 'Backup & Restore',
          subtitle: 'Back up or restore system data',
          onTap: () => _adminOnly(const AdminInfoScreen(
            title: 'Backup & Restore',
            subtitle: 'Protect and recover platform data.',
            icon: Icons.cloud_upload_outlined,
            color: MedsColors.amber,
            bullets: [
              'Data lives in managed Supabase Postgres with automatic backups.',
              'Use the Supabase dashboard for point-in-time restore.',
              'In-app backup scheduling is part of the admin roadmap.',
            ],
          )),
        ),
      ]),
    ];
  }

  Widget _logout() {
    return SettingsGroupCard(
      color: MedsColors.red.withValues(alpha: 0.07),
      children: [
        SettingRow(
          icon: Icons.logout,
          color: MedsColors.red,
          title: 'Log Out',
          subtitle: 'Sign out from the admin panel',
          danger: true,
          onTap: _confirmLogout,
        ),
      ],
    );
  }
}

class _BellButton extends StatelessWidget {
  final VoidCallback onTap;
  const _BellButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: notifications,
      builder: (context, _) {
        final unread = notifications.unreadCount > 0;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_outlined,
                  color: MedsColors.lightText),
              tooltip: 'Notifications',
              onPressed: onTap,
            ),
            if (unread)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: MedsColors.purple,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
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
        title: 'Failed to load settings',
        message: 'Something went wrong while loading your settings.',
        action: FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Try Again'),
        ),
      ),
    );
  }
}
