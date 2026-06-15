import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../main.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'admin/admin_home_screen.dart';

/// After sign-in, loads the user's profile and routes to the correct app:
/// the admin panel for `role = 'admin'`, a blocked notice for disabled
/// accounts, otherwise the normal user shell.
class RoleRouter extends StatefulWidget {
  final List<CameraDescription> cameras;

  const RoleRouter({super.key, required this.cameras});

  @override
  State<RoleRouter> createState() => _RoleRouterState();
}

class _RoleRouterState extends State<RoleRouter> {
  final _auth = AuthService();
  bool _loading = true;
  bool _isAdmin = false;
  bool _isBlocked = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    try {
      final profile = await _auth.loadProfile();
      if (!mounted) return;
      setState(() {
        _isAdmin = profile.isAdmin;
        _isBlocked = profile.isBlocked;
        _loading = false;
      });
    } catch (_) {
      // If the profile can't load, fall back to the normal user app.
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: medsGreen)),
      );
    }
    if (_isBlocked) return const _BlockedScreen();
    if (_isAdmin) return const AdminHomeScreen();
    return MainShell(cameras: widget.cameras);
  }
}

class _BlockedScreen extends StatelessWidget {
  const _BlockedScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.block, size: 72, color: Colors.red.shade400),
              const SizedBox(height: 16),
              const Text(
                'Account blocked',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your account has been disabled by an administrator. '
                'Please contact support if you believe this is a mistake.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () => AuthService().signOut(),
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
