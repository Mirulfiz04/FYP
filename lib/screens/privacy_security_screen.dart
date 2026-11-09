import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/auth_service.dart';
import '../services/data_export_service.dart';
import '../services/export_history_service.dart';
import '../theme/app_theme.dart';
import '../widgets/email_export_sheet.dart';
import '../widgets/ui_kit.dart';

const Color _accent = Color(0xFF6A5AE0);

class PrivacySecurityScreen extends StatefulWidget {
  const PrivacySecurityScreen({super.key});

  @override
  State<PrivacySecurityScreen> createState() => _PrivacySecurityScreenState();
}

class _PrivacySecurityScreenState extends State<PrivacySecurityScreen> {
  // Lazy so the screen can be pumped in tests without initializing Supabase
  // (only created when a security action is actually invoked).
  late final _auth = AuthService();
  bool _biometric = false;
  bool _storeData = true;
  bool _busy = false;
  Future<ExportRecord?>? _lastExport;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _refreshLastExport();
  }

  void _refreshLastExport() {
    if (!mounted) return;
    setState(() {
      _lastExport = ExportHistoryService().lastForScope('all');
    });
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _biometric = prefs.getBool('biometric_enabled') ?? false;
      _storeData = prefs.getBool('store_session_data') ?? true;
    });
  }

  Future<void> _setPref(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red.shade700 : null,
    ));
  }

  Future<bool> _confirm(String title, String message, String confirmLabel) async {
    final ok = await showDialog<bool>(
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
            style: FilledButton.styleFrom(backgroundColor: MedsColors.red),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _changePassword() async {
    final email = _auth.currentUser?.email;
    if (email == null) return;
    try {
      await _auth.resetPassword(email);
      _snack('Password reset link sent to $email');
    } catch (_) {
      _snack('Could not send reset email.', error: true);
    }
  }

  Future<void> _signOutEverywhere() async {
    if (!await _confirm('Sign out from all devices?',
        'You will be signed out everywhere and need to log in again.',
        'Sign out')) {
      return;
    }
    try {
      await _auth.signOutEverywhere();
    } catch (_) {
      _snack('Could not sign out everywhere.', error: true);
    }
  }

  Future<void> _deleteHistory() async {
    if (!await _confirm('Delete session history?',
        'This permanently removes all your sessions and readings. This cannot '
            'be undone.',
        'Delete')) {
      return;
    }
    setState(() => _busy = true);
    try {
      await _auth.deleteSessionHistory();
      _snack('Session history deleted.');
    } catch (_) {
      _snack('Could not delete history.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteAccount() async {
    if (!await _confirm('Delete account?',
        'This removes all your data and signs you out. This cannot be undone.',
        'Delete account')) {
      return;
    }
    setState(() => _busy = true);
    try {
      await _auth.deleteAccountData(); // signs out -> AuthGate shows Login
    } catch (_) {
      if (mounted) setState(() => _busy = false);
      _snack('Could not delete account.', error: true);
    }
  }

  Future<void> _exportMyData() async {
    final myEmail = _auth.currentUser?.email;
    final sent = await showEmailExportSheet(
      context,
      title: 'Export & email my data',
      subject: 'My MEDS data export',
      myEmail: myEmail,
      historyScope: 'all',
      builder: ({required bool includeCsv, required bool includePdf}) =>
          DataExportService().loadFullExport(
        includeCsv: includeCsv,
        includePdf: includePdf,
      ),
    );
    if (sent) _refreshLastExport();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy & Security')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SectionHeader(
                title: 'Account security',
                icon: Icons.lock_outline,
                color: _accent),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.password, color: _accent),
                    title: const Text('Change password'),
                    subtitle: const Text('We will email you a reset link'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _changePassword,
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    activeThumbColor: _accent,
                    secondary:
                        const Icon(Icons.fingerprint, color: _accent),
                    title: const Text('Biometric login'),
                    subtitle: const Text('Requires device support'),
                    value: _biometric,
                    onChanged: (v) {
                      setState(() => _biometric = v);
                      _setPref('biometric_enabled', v);
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.devices_other, color: _accent),
                    title: const Text('Sign out from all devices'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _signOutEverywhere,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const SectionHeader(
                title: 'Permissions',
                icon: Icons.verified_user_outlined,
                color: MedsColors.teal),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: const [
                  ListTile(
                    leading: Icon(Icons.camera_alt_outlined, color: _accent),
                    title: Text('Camera access'),
                    subtitle: Text('Managed in your device settings'),
                  ),
                  Divider(height: 1),
                  ListTile(
                    leading:
                        Icon(Icons.notifications_outlined, color: _accent),
                    title: Text('Notification access'),
                    subtitle: Text('Managed in your device settings'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const SectionHeader(
                title: 'Data & privacy',
                icon: Icons.privacy_tip_outlined,
                color: MedsColors.amber),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  const ExpansionTile(
                    leading: Icon(Icons.policy_outlined, color: _accent),
                    title: Text('Data privacy notice'),
                    childrenPadding:
                        EdgeInsets.fromLTRB(16, 0, 16, 14),
                    children: [
                      Text(
                        'MEDS stores your facial-emotion results and heart-rate '
                        'readings to your account so you can review your '
                        'wellbeing over time. Your data is private to you (and '
                        'an administrator for support). It is never sold.',
                        style: TextStyle(fontSize: 13, height: 1.4),
                      ),
                    ],
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    activeThumbColor: _accent,
                    secondary: const Icon(Icons.save_outlined, color: _accent),
                    title: const Text('Store session data'),
                    subtitle:
                        const Text('Save readings to your account'),
                    value: _storeData,
                    onChanged: (v) {
                      setState(() => _storeData = v);
                      _setPref('store_session_data', v);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const SectionHeader(
                title: 'Export data',
                icon: Icons.ios_share_outlined,
                color: MedsColors.blue),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                leading: const Icon(Icons.mark_email_read_outlined,
                    color: MedsColors.blue),
                title: const Text('Export & email my data'),
                subtitle: FutureBuilder<ExportRecord?>(
                  future: _lastExport,
                  builder: (context, snap) {
                    final r = snap.data;
                    if (r == null) {
                      return const Text(
                          'Send your sessions & readings as PDF + CSV to any email');
                    }
                    final when =
                        DateFormat('d MMM yyyy').format(r.sentAt.toLocal());
                    final what = r.method == 'file'
                        ? 'Last shared as file'
                        : 'Last sent to ${r.recipient}';
                    return Text('$what · $when',
                        style: const TextStyle(color: MedsColors.blue));
                  },
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _exportMyData,
              ),
            ),
            const SizedBox(height: 16),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.delete_sweep_outlined,
                        color: MedsColors.red),
                    title: const Text('Delete session history',
                        style: TextStyle(color: MedsColors.red)),
                    onTap: _deleteHistory,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.no_accounts_outlined,
                        color: MedsColors.red),
                    title: const Text('Delete account',
                        style: TextStyle(color: MedsColors.red)),
                    onTap: _deleteAccount,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
