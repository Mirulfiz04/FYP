import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import 'register_screen.dart';

/// Accent colour for this screen — shared with the register screen.
/// Defined once in app_theme.dart (`authAccent`) so both stay in sync.
const Color _accent = authAccent;

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _auth = AuthService();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _loading = false;
  bool _obscure = true;
  bool _remember = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await _auth.signIn(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
      // AuthGate reacts to the auth state change and swaps in the app shell.
    } on AuthException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Sign in failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final emailCtrl = TextEditingController(text: _emailCtrl.text.trim());
    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter your account email and we\'ll send you a reset link.',
              style: TextStyle(color: MedsColors.muted, fontSize: 13.5),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, emailCtrl.text.trim()),
            child: const Text('Send Link'),
          ),
        ],
      ),
    );

    if (email == null || email.isEmpty || !email.contains('@')) return;
    try {
      await _auth.resetPassword(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reset link sent to $email')),
      );
    } catch (e) {
      _showError('Could not send reset email: $e');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Soft top-to-bottom tint that echoes the mockup's gentle background.
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).scaffoldBackgroundColor,
              _accent.withValues(alpha: 0.10),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ─────────────────────────────────────────────────────────
                    //  HERO IMAGE
                    //  Drop your illustration at: assets/images/login_hero.png
                    //  Until that file exists, the branded placeholder below
                    //  is shown automatically — no code change needed.
                    // ─────────────────────────────────────────────────────────
                    _HeroImage(),
                    const SizedBox(height: 18),

                    // Branded app title.
                    Text.rich(
                      const TextSpan(
                        children: [
                          TextSpan(
                              text: 'MEDS', style: TextStyle(color: _accent)),
                        ],
                      ),
                      textAlign: TextAlign.center,
                      style:
                          Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                height: 1.15,
                              ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Understand. Monitor. Improve.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: MedsColors.muted, fontSize: 14),
                    ),
                    const SizedBox(height: 10),
                    const Icon(Icons.favorite, color: _accent, size: 18),
                    const SizedBox(height: 24),

                    // ── Login card ──
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: softShadow(context),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Welcome Back!',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Please login to continue',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: MedsColors.muted, fontSize: 13.5),
                          ),
                          const SizedBox(height: 22),

                          // Email
                          TextFormField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              hintText: 'Email',
                              prefixIcon:
                                  Icon(Icons.person_outline, color: _accent),
                            ),
                            validator: (v) => (v == null || !v.contains('@'))
                                ? 'Enter a valid email'
                                : null,
                          ),
                          const SizedBox(height: 14),

                          // Password
                          TextFormField(
                            controller: _passwordCtrl,
                            obscureText: _obscure,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _signIn(),
                            decoration: InputDecoration(
                              hintText: 'Password',
                              prefixIcon: const Icon(Icons.lock_outline,
                                  color: _accent),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: MedsColors.muted,
                                ),
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                              ),
                            ),
                            validator: (v) => (v == null || v.isEmpty)
                                ? 'Enter your password'
                                : null,
                          ),
                          const SizedBox(height: 6),

                          // Remember me  +  Forgot password
                          Row(
                            children: [
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: Checkbox(
                                  value: _remember,
                                  activeColor: _accent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  onChanged: (v) =>
                                      setState(() => _remember = v ?? false),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text('Remember me',
                                  style: TextStyle(color: MedsColors.muted)),
                              const Spacer(),
                              TextButton(
                                style: TextButton.styleFrom(
                                  foregroundColor: _accent,
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(0, 0),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: _loading ? null : _forgotPassword,
                                child: const Text('Forgot Password?'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),

                          // Login
                          FilledButton(
                            onPressed: _loading ? null : _signIn,
                            style: FilledButton.styleFrom(
                              backgroundColor: _accent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: _loading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text('Login'),
                          ),
                          const SizedBox(height: 18),

                          // OR divider
                          Row(
                            children: [
                              const Expanded(child: Divider()),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                child: Text('OR',
                                    style: TextStyle(
                                        color: MedsColors.muted,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12)),
                              ),
                              const Expanded(child: Divider()),
                            ],
                          ),
                          const SizedBox(height: 18),

                          // Create account
                          OutlinedButton.icon(
                            onPressed: _loading
                                ? null
                                : () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => const RegisterScreen(),
                                      ),
                                    ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _accent,
                              side: BorderSide(
                                  color: _accent.withValues(alpha: 0.5)),
                              padding: const EdgeInsets.symmetric(vertical: 15),
                            ),
                            icon: const Icon(Icons.person_add_alt_1, size: 20),
                            label: const Text('Create New Account'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),

                    // Footer features
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _footerFeature(
                            Icons.verified_user_outlined, 'Secure Login'),
                        Container(
                          width: 1,
                          height: 22,
                          color: Theme.of(context).dividerColor,
                          margin: const EdgeInsets.symmetric(horizontal: 18),
                        ),
                        _footerFeature(
                            Icons.bar_chart_rounded, 'Real-time Analysis'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _footerFeature(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: _accent),
        const SizedBox(width: 8),
        Text(label,
            style: const TextStyle(
                color: MedsColors.muted,
                fontSize: 13,
                fontWeight: FontWeight.w500)),
      ],
    );
  }
}

/// The hero artwork at the top of the login screen.
///
/// It tries to load `assets/images/login_hero.png`. If you haven't added that
/// file yet, [errorBuilder] shows a branded placeholder so the screen still
/// looks complete. To use your own art, just drop the PNG into
/// `assets/images/` — it's already registered in pubspec.yaml.
class _HeroImage extends StatelessWidget {
  const _HeroImage();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 170,
      child: Image.asset(
        'assets/images/login_hero.png',
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const _HeroPlaceholder(),
      ),
    );
  }
}

class _HeroPlaceholder extends StatelessWidget {
  const _HeroPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Soft glow blob behind the disc.
        Container(
          width: 158,
          height: 158,
          decoration: BoxDecoration(
            color: _accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(70),
          ),
        ),
        // White disc with the face icon.
        Container(
          width: 122,
          height: 122,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            shape: BoxShape.circle,
            boxShadow: softShadow(context),
          ),
          child: const Icon(Icons.face_retouching_natural,
              size: 64, color: _accent),
        ),
        // Scan frame hint.
        Icon(Icons.center_focus_weak,
            size: 120, color: _accent.withValues(alpha: 0.35)),
        // Heart-rate badge, bottom-left.
        Positioned(
          bottom: 22,
          left: 110,
          child: Container(
            padding: const EdgeInsets.all(9),
            decoration: const BoxDecoration(
              color: _accent,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.monitor_heart_outlined,
                size: 20, color: Colors.white),
          ),
        ),
      ],
    );
  }
}
