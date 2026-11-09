import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/profile_repository.dart';
import '../theme/app_theme.dart';
import '../viewmodels/profile_view_model.dart';
import '../widgets/profile_header_card.dart';
import '../widgets/profile_menu_item.dart';
import '../widgets/ui_kit.dart';
import 'about_app_screen.dart';
import 'appearance_screen.dart';
import 'connected_devices_screen.dart';
import 'edit_profile_screen.dart';
import 'help_support_screen.dart';
import 'notification_settings_screen.dart';
import 'personal_information_screen.dart';
import 'privacy_security_screen.dart';

const Color _accent = Color(0xFF6A5AE0);

/// The Profile tab: account header, settings menu and secure logout.
///
/// [repository] and [onSignOut] are injectable for testing; in the app they
/// default to the real Supabase-backed implementations.
class ProfileScreen extends StatefulWidget {
  final ProfileRepository? repository;
  final Future<void> Function()? onSignOut;

  const ProfileScreen({super.key, this.repository, this.onSignOut});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final _vm =
      ProfileViewModel(repository: widget.repository ?? SupabaseProfileRepository());

  @override
  void initState() {
    super.initState();
    _vm.load();
  }

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  void _push(Widget screen) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => screen));

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('Are you sure you want to log out?'),
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
    // Signing out flips the auth state; AuthGate swaps in the Login screen and
    // drops the protected navigation stack, so the back button can't return.
    if (ok == true) {
      final signOut = widget.onSignOut ?? () => AuthService().signOut();
      await signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _vm,
          builder: (context, _) {
            return RefreshIndicator(
              onRefresh: _vm.refresh,
              color: _accent,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  _topBar(),
                  const SizedBox(height: 12),
                  ..._body(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _topBar() {
    return const Align(
      alignment: Alignment.centerLeft,
      child: Text('Profile',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
    );
  }

  List<Widget> _body() {
    if (_vm.loading && _vm.profile == null) {
      return const [
        SizedBox(
          height: 320,
          child: Center(child: CircularProgressIndicator(color: _accent)),
        ),
      ];
    }

    final profile = _vm.profile;
    if (profile == null) {
      return [
        SizedBox(
          height: 320,
          child: EmptyState(
            icon: Icons.person_off_outlined,
            title: 'Could not load your profile',
            message: 'Pull down to retry.',
            color: MedsColors.red,
            action: FilledButton.icon(
              onPressed: _vm.refresh,
              style: FilledButton.styleFrom(backgroundColor: _accent),
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ),
        ),
      ];
    }

    return [
      ProfileHeaderCard(
        profile: profile,
        onEdit: () => _push(EditProfileScreen(vm: _vm)),
      ),
      const SizedBox(height: 20),
      ProfileMenuItem(
        icon: Icons.person_outline,
        title: 'Personal Information',
        onTap: () => _push(PersonalInformationScreen(vm: _vm)),
      ),
      ProfileMenuItem(
        icon: Icons.notifications_outlined,
        title: 'Notification Preferences',
        onTap: () => _push(const NotificationSettingsScreen()),
      ),
      ProfileMenuItem(
        icon: Icons.smartphone_outlined,
        title: 'Connected Devices',
        onTap: () => _push(const ConnectedDevicesScreen()),
      ),
      ProfileMenuItem(
        icon: Icons.shield_outlined,
        title: 'Privacy & Security',
        onTap: () => _push(const PrivacySecurityScreen()),
      ),
      ProfileMenuItem(
        icon: Icons.headset_mic_outlined,
        title: 'Help & Support',
        onTap: () => _push(const HelpSupportScreen()),
      ),
      ProfileMenuItem(
        icon: Icons.info_outline,
        title: 'About App',
        onTap: () => _push(const AboutAppScreen()),
      ),
      ProfileMenuItem(
        icon: Icons.palette_outlined,
        title: 'Appearance',
        onTap: () => _push(const AppearanceScreen()),
      ),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: _logout,
          style: FilledButton.styleFrom(
            backgroundColor: MedsColors.red.withValues(alpha: 0.12),
            foregroundColor: MedsColors.red,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: const Text('Log Out',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        ),
      ),
    ];
  }
}
