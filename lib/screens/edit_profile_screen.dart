import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../viewmodels/profile_view_model.dart';

const Color _accent = Color(0xFF6A5AE0);

const _ageGroups = ['Under 18', '18–24', '25–34', '35–44', '45–54', '55+'];
const _genders = ['Male', 'Female', 'Other', 'Prefer not to say'];
const _categories = ['Student', 'Employee', 'Researcher', 'Other'];
const _goals = [
  'Stress monitoring',
  'Emotional awareness',
  'Study monitoring',
];

/// Edits the user's profile. Shares the [ProfileViewModel] with the Profile
/// screen so the header updates immediately after a successful save.
class EditProfileScreen extends StatefulWidget {
  final ProfileViewModel vm;
  const EditProfileScreen({super.key, required this.vm});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();

  late final _nameCtrl = TextEditingController();
  late final _displayCtrl = TextEditingController();
  late final _emailCtrl = TextEditingController();
  String? _ageGroup;
  String? _gender;
  String? _category;
  String? _goal;
  bool _avatarBusy = false;

  @override
  void initState() {
    super.initState();
    final p = widget.vm.profile;
    _nameCtrl.text = p?.name ?? '';
    _displayCtrl.text = p?.displayName ?? '';
    _emailCtrl.text = p?.email ?? '';
    _ageGroup = _ageGroups.contains(p?.ageGroup) ? p?.ageGroup : null;
    _gender = _genders.contains(p?.gender) ? p?.gender : null;
    _category = _categories.contains(p?.userCategory) ? p?.userCategory : null;
    _goal = _goals.contains(p?.monitoringGoal) ? p?.monitoringGoal : null;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _displayCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
          source: source, maxWidth: 800, maxHeight: 800, imageQuality: 85);
      if (picked == null) return;
      setState(() => _avatarBusy = true);
      final ok = await widget.vm.uploadAvatar(File(picked.path));
      if (!mounted) return;
      _snack(ok ? 'Profile picture updated' : 'Upload failed', error: !ok);
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  void _showAvatarOptions() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () {
              Navigator.pop(ctx);
              _pickAvatar(ImageSource.gallery);
            },
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined),
            title: const Text('Take a photo'),
            onTap: () {
              Navigator.pop(ctx);
              _pickAvatar(ImageSource.camera);
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final current = widget.vm.profile;
    if (current == null) return;

    final updated = current.copyWith(
      name: _nameCtrl.text.trim(),
      displayName: _displayCtrl.text.trim(),
      ageGroup: _ageGroup,
      gender: _gender,
      userCategory: _category,
      monitoringGoal: _goal,
    );
    final ok = await widget.vm.save(updated);
    if (!mounted) return;
    if (ok) {
      _snack('Profile updated');
      Navigator.of(context).pop(true);
    } else {
      _snack('Could not save. Please try again.', error: true);
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red.shade700 : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: ListenableBuilder(
        listenable: widget.vm,
        builder: (context, _) {
          final saving = widget.vm.saving;
          final avatarUrl = widget.vm.profile?.avatarUrl;
          final hasAvatar = avatarUrl != null && avatarUrl.isNotEmpty;
          return AbsorbPointer(
            absorbing: saving,
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Center(child: _avatar(hasAvatar, avatarUrl)),
                  const SizedBox(height: 22),
                  TextFormField(
                    controller: _nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Full name',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Enter your name'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _displayCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Display name (optional)',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email address',
                      prefixIcon: Icon(Icons.email_outlined),
                      helperText: 'To change your login email, contact support.',
                    ),
                    validator: (v) => ProfileViewModel.emailIsValid(v ?? '')
                        ? null
                        : 'Enter a valid email',
                  ),
                  const SizedBox(height: 14),
                  _dropdown('Age group', Icons.cake_outlined, _ageGroup,
                      _ageGroups, (v) => setState(() => _ageGroup = v)),
                  const SizedBox(height: 14),
                  _dropdown('Gender (optional)', Icons.wc_outlined, _gender,
                      _genders, (v) => setState(() => _gender = v)),
                  const SizedBox(height: 14),
                  _dropdown('User category', Icons.groups_outlined, _category,
                      _categories, (v) => setState(() => _category = v)),
                  const SizedBox(height: 14),
                  _dropdown('Monitoring goal', Icons.flag_outlined, _goal,
                      _goals, (v) => setState(() => _goal = v)),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: _accent,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Save Changes'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: saving ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _avatar(bool hasAvatar, String? url) {
    return Stack(
      children: [
        CircleAvatar(
          radius: 48,
          backgroundColor: _accent.withValues(alpha: 0.15),
          backgroundImage: hasAvatar ? NetworkImage(url!) : null,
          child: _avatarBusy
              ? const CircularProgressIndicator(color: _accent)
              : (hasAvatar
                  ? null
                  : Text(widget.vm.profile?.initials ?? '?',
                      style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: _accent))),
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: Material(
            color: _accent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _avatarBusy ? null : _showAvatarOptions,
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.edit, size: 16, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _dropdown(String label, IconData icon, String? value,
      List<String> items, ValueChanged<String?> onChanged) {
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
}
