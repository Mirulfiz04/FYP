import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth/login_screen.dart';
import 'role_router.dart';

/// Shows the login screen when signed out and routes by role when signed in.
class AuthGate extends StatelessWidget {
  final List<CameraDescription> cameras;

  const AuthGate({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, _) {
        final session = Supabase.instance.client.auth.currentSession;
        if (session != null) {
          // Re-resolve role/status for whoever is currently signed in.
          return RoleRouter(key: ValueKey(session.user.id), cameras: cameras);
        }
        return const LoginScreen();
      },
    );
  }
}
