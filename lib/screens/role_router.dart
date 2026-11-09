import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../main.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'admin/admin_shell.dart';

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
  bool _isInactive = false;

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
        _isInactive = profile.isInactive;
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
    // An administrator can disable an account by blocking OR deactivating it;
    // both keep the user out of the app until re-enabled.
    if (_isBlocked || _isInactive) {
      return _DisabledScreen(blocked: _isBlocked);
    }
    if (_isAdmin) return const AdminShell();
    return MainShell(cameras: widget.cameras);
  }
}

class _DisabledScreen extends StatelessWidget {
  final bool blocked;
  const _DisabledScreen({required this.blocked});

  @override
  Widget build(BuildContext context) {
    final title = blocked ? 'Account blocked' : 'Account deactivated';
    final message = blocked
        ? 'Your account has been blocked by an administrator. Please contact '
            'support if you believe this is a mistake.'
        : 'Your account has been deactivated by an administrator. Please '
            'contact support to have it reactivated.';
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(blocked ? Icons.block : Icons.pause_circle_outline,
                  size: 72, color: Colors.red.shade400),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
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
