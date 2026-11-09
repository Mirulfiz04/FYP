import 'package:flutter/material.dart';

import '../../services/admin_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/admin/user_badges.dart';
import '../../widgets/ui_kit.dart';

/// Administrator form for creating a new account. The sign-up runs on a
/// throwaway client (see [AdminService.createUser]) so the administrator stays
/// signed in. Passwords are never displayed back or stored in plain text here.
class AdminAddUserScreen extends StatefulWidget {
  const AdminAddUserScreen({super.key});

  @override
  State<AdminAddUserScreen> createState() => _AdminAddUserScreenState();
}

class _AdminAddUserScreenState extends State<AdminAddUserScreen> {
  final _admin = AdminService();
  final _form = GlobalKey<FormState>();

  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  String _role = 'user';
  String _status = 'active';
  bool _notify = true;
  bool _obscure = true;
  bool _submitting = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return; // prevent duplicate requests
    if (!(_form.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);
    try {
      await _admin.createUser(
        name: _name.text.trim(),
        email: _email.text.trim(),
        password: _password.text,
        role: _role,
        status: _status,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: MedsColors.red,
          content: Text('Could not create user: $e'),
        ));
      }
    }
  }

  String? _required(String? v, String field) =>
      (v == null || v.trim().isEmpty) ? '$field is required' : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add User')),
      body: AbsorbPointer(
        absorbing: _submitting,
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Full name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) => _required(v, 'Full name'),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email address',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: (v) {
                  final value = v?.trim() ?? '';
                  if (value.isEmpty) return 'Email is required';
                  final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+').hasMatch(value);
                  return ok ? null : 'Enter a valid email';
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _password,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'Temporary password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                        _obscure ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (v) => (v == null || v.length < 6)
                    ? 'Use at least 6 characters'
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _confirm,
                obscureText: _obscure,
                decoration: const InputDecoration(
                  labelText: 'Confirm password',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                validator: (v) =>
                    v != _password.text ? 'Passwords do not match' : null,
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(
                  labelText: 'Role',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
                items: const ['user', 'viewer', 'operator', 'researcher', 'admin']
                    .map((r) =>
                        DropdownMenuItem(value: r, child: Text(roleLabel(r))))
                    .toList(),
                onChanged: (v) => setState(() => _role = v ?? _role),
              ),
              if (_role == 'admin')
                const Padding(
                  padding: EdgeInsets.only(top: 6, left: 4),
                  child: Text(
                    'Admin accounts have full management access. Assign with care.',
                    style: TextStyle(color: MedsColors.amber, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(
                  labelText: 'Account status',
                  prefixIcon: Icon(Icons.verified_user_outlined),
                ),
                items: const ['active', 'inactive']
                    .map((s) =>
                        DropdownMenuItem(value: s, child: Text(statusLabel(s))))
                    .toList(),
                onChanged: (v) => setState(() => _status = v ?? _status),
              ),
              const SizedBox(height: 6),
              CheckboxListTile(
                value: _notify,
                onChanged: (v) => setState(() => _notify = v ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Send account notification'),
                subtitle: const Text(
                    'Let the user know their account was created.'),
              ),
              const SizedBox(height: 12),
              AppCard(
                color: MedsColors.blue.withValues(alpha: 0.08),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: MedsColors.blue, size: 18),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'The user signs in with this temporary password and can '
                        'change it later. Email confirmation must be off for '
                        'immediate access.',
                        style: TextStyle(fontSize: 12, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 50,
                child: FilledButton.icon(
                  onPressed: _submitting ? null : _submit,
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.4, color: Colors.white))
                      : const Icon(Icons.person_add_alt_1),
                  label: Text(_submitting ? 'Creating…' : 'Create User'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
