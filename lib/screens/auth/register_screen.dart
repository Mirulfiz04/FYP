import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui_kit.dart';

/// Accent colour — shared with the login screen via `authAccent`.
const Color _accent = authAccent;

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _auth = AuthService();

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _categoryOtherCtrl = TextEditingController();

  String? _ageGroup;
  String? _gender;
  String? _category;
  String? _goal;
  String _notify = 'All';

  bool _loading = false;
  bool _obscure = true;
  bool _obscureConfirm = true;
  bool _privacyConsent = false;
  bool _researchAck = false;

  static const _ageGroups = [
    'Under 18',
    '18–24',
    '25–34',
    '35–44',
    '45–54',
    '55+',
  ];
  static const _genders = ['Male', 'Female', 'Other', 'Prefer not to say'];
  static const _categories = ['Student', 'Employee', 'Other'];
  static const _goals = [
    'Stress monitoring',
    'Emotional awareness',
    'Study monitoring',
  ];
  static const _notifyOptions = ['All', 'Important only', 'None'];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _categoryOtherCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_privacyConsent) {
      _showError('Please accept the privacy consent to create an account.');
      return;
    }
    if (!_researchAck) {
      _showError('Please acknowledge the research-use notice.');
      return;
    }
    setState(() => _loading = true);
    try {
      final hasSession = await _auth.signUp(
        name: _nameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
        privacyConsent: _privacyConsent,
        researchAck: _researchAck,
        ageGroup: _ageGroup,
        gender: _gender,
        userCategory: _category,
        userCategoryOther:
            _category == 'Other' ? _categoryOtherCtrl.text.trim() : null,
        monitoringGoal: _goal,
        notificationPref: _notify,
      );
      if (!mounted) return;

      if (hasSession) {
        // Signed in immediately — AuthGate will show the app shell.
        Navigator.of(context).pop();
      } else {
        // Email confirmation is enabled; prompt the user to confirm.
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Account created. Check your email to confirm, then sign in.'),
          ),
        );
      }
    } on AuthException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Registration failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: MedsColors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Same gentle background tint as the login screen.
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Back to login.
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      onPressed:
                          _loading ? null : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back),
                      tooltip: 'Back to login',
                    ),
                  ),
                  const SizedBox(height: 4),

                  // Hero disc — matches the login placeholder style.
                  Center(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: _accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(54),
                          ),
                        ),
                        Container(
                          width: 92,
                          height: 92,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            shape: BoxShape.circle,
                            boxShadow: softShadow(context),
                          ),
                          child: const Icon(Icons.person_add_alt_1,
                              size: 46, color: _accent),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Two-tone title, like the login screen.
                  Text.rich(
                    TextSpan(
                      children: const [
                        TextSpan(text: 'Create Your '),
                        TextSpan(
                          text: 'Account',
                          style: TextStyle(color: _accent),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Join MEDS to track your emotions & wellbeing',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: MedsColors.muted, fontSize: 13.5),
                  ),
                  const SizedBox(height: 24),

                  // ── Section 1: Account (required) ──
                  const SectionHeader(
                    title: 'Account',
                    icon: Icons.lock_outline,
                    color: _accent,
                  ),
                  _Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _nameCtrl,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Full name or display name',
                            prefixIcon:
                                Icon(Icons.person_outline, color: _accent),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Enter your name'
                              : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Email address',
                            prefixIcon:
                                Icon(Icons.email_outlined, color: _accent),
                          ),
                          validator: (v) => (v == null || !v.contains('@'))
                              ? 'Enter a valid email'
                              : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _passwordCtrl,
                          obscureText: _obscure,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon:
                                const Icon(Icons.lock_outline, color: _accent),
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
                          validator: (v) => (v == null || v.length < 6)
                              ? 'At least 6 characters'
                              : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _confirmCtrl,
                          obscureText: _obscureConfirm,
                          textInputAction: TextInputAction.done,
                          decoration: InputDecoration(
                            labelText: 'Confirm password',
                            prefixIcon: const Icon(Icons.lock_reset_outlined,
                                color: _accent),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureConfirm
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: MedsColors.muted,
                              ),
                              onPressed: () => setState(
                                  () => _obscureConfirm = !_obscureConfirm),
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return 'Confirm your password';
                            }
                            if (v != _passwordCtrl.text) {
                              return 'Passwords do not match';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Section 2: About you (optional) ──
                  const SectionHeader(
                    title: 'About you  ·  optional',
                    icon: Icons.insights_outlined,
                    color: MedsColors.blue,
                  ),
                  _Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Helps us group and compare results. You can skip any '
                          'of these.',
                          style:
                              TextStyle(color: MedsColors.muted, fontSize: 12.5),
                        ),
                        const SizedBox(height: 14),
                        _dropdown(
                          label: 'Age group',
                          icon: Icons.cake_outlined,
                          value: _ageGroup,
                          items: _ageGroups,
                          onChanged: (v) => setState(() => _ageGroup = v),
                        ),
                        const SizedBox(height: 14),
                        _dropdown(
                          label: 'Gender',
                          icon: Icons.wc_outlined,
                          value: _gender,
                          items: _genders,
                          onChanged: (v) => setState(() => _gender = v),
                        ),
                        const SizedBox(height: 14),
                        _dropdown(
                          label: 'User category',
                          icon: Icons.groups_outlined,
                          value: _category,
                          items: _categories,
                          onChanged: (v) => setState(() => _category = v),
                        ),
                        // When "Other" is picked, let them describe their role.
                        if (_category == 'Other') ...[
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _categoryOtherCtrl,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'Please specify your category',
                              hintText: 'e.g. Doctor, Worker, Teacher',
                              prefixIcon:
                                  Icon(Icons.edit_outlined, color: _accent),
                            ),
                            validator: (v) => (_category == 'Other' &&
                                    (v == null || v.trim().isEmpty))
                                ? 'Tell us your category'
                                : null,
                          ),
                        ],
                        const SizedBox(height: 14),
                        _dropdown(
                          label: 'Preferred monitoring goal',
                          icon: Icons.flag_outlined,
                          value: _goal,
                          items: _goals,
                          onChanged: (v) => setState(() => _goal = v),
                        ),
                        const SizedBox(height: 14),
                        _dropdown(
                          label: 'Notification preference',
                          icon: Icons.notifications_outlined,
                          value: _notify,
                          items: _notifyOptions,
                          onChanged: (v) =>
                              setState(() => _notify = v ?? 'All'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Consent (required) ──
                  _consentTile(
                    value: _privacyConsent,
                    onChanged: (v) =>
                        setState(() => _privacyConsent = v ?? false),
                    color: _accent,
                    icon: Icons.privacy_tip_outlined,
                    text:
                        'I consent to MEDS storing and processing my facial-'
                        'expression and heart-rate data for emotion and '
                        'wellbeing analysis.',
                  ),
                  const SizedBox(height: 12),
                  _consentTile(
                    value: _researchAck,
                    onChanged: (v) => setState(() => _researchAck = v ?? false),
                    color: MedsColors.amber,
                    icon: Icons.science_outlined,
                    text:
                        'I understand MEDS is for emotional awareness and '
                        'research purposes only, and is not a medical '
                        'diagnostic tool.',
                  ),
                  const SizedBox(height: 20),

                  // Create account.
                  FilledButton(
                    onPressed: _loading ? null : _register,
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
                        : const Text('Create Account'),
                  ),
                  const SizedBox(height: 14),

                  // Back to login link.
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Already have an account?',
                          style: TextStyle(color: MedsColors.muted)),
                      TextButton(
                        style: TextButton.styleFrom(foregroundColor: _accent),
                        onPressed:
                            _loading ? null : () => Navigator.of(context).pop(),
                        child: const Text('Login'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dropdown({
    required String label,
    required IconData icon,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: _accent),
      ),
      items: items
          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
          .toList(),
      onChanged: onChanged,
    );
  }

  Widget _consentTile({
    required bool value,
    required ValueChanged<bool?> onChanged,
    required Color color,
    required IconData icon,
    required String text,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: CheckboxListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        controlAffinity: ListTileControlAffinity.leading,
        activeColor: color,
        value: value,
        onChanged: onChanged,
        secondary: Icon(icon, color: color),
        title: Text(text, style: const TextStyle(fontSize: 12.5, height: 1.35)),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) =>
      AppCard(padding: const EdgeInsets.all(18), child: child);
}
