import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/sensor_config.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _auth = AuthService();
  final _picker = ImagePicker();

  final _nameCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _sensorCtrl =
      TextEditingController(text: sensorConfig.hostForDisplay);
  String? _gender;

  UserProfile? _profile;
  bool _loading = true;
  bool _saving = false;
  bool _avatarBusy = false;

  static const _genders = ['Male', 'Female', 'Other', 'Prefer not to say'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    _contactCtrl.dispose();
    _locationCtrl.dispose();
    _sensorCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveSensor() async {
    await sensorConfig.setFromInput(_sensorCtrl.text);
    if (!mounted) return;
    _sensorCtrl.text = sensorConfig.hostForDisplay;
    _snack('Sensor address saved (${sensorConfig.hostForDisplay})');
  }

  Future<void> _load() async {
    try {
      final profile = await _auth.loadProfile();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _nameCtrl.text = profile.name ?? '';
        _ageCtrl.text = profile.age?.toString() ?? '';
        _contactCtrl.text = profile.contactNumber ?? '';
        _locationCtrl.text = profile.location ?? '';
        _gender = _genders.contains(profile.gender) ? profile.gender : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('Could not load profile: $e', error: true);
    }
  }

  Future<void> _save() async {
    final current = _profile;
    if (current == null) return;
    setState(() => _saving = true);
    try {
      final updated = current.copyWith(
        name: _nameCtrl.text.trim(),
        age: int.tryParse(_ageCtrl.text.trim()),
        gender: _gender,
        contactNumber: _contactCtrl.text.trim(),
        location: _locationCtrl.text.trim(),
      );
      await _auth.saveProfile(updated);
      if (!mounted) return;
      setState(() => _profile = updated);
      _snack('Profile saved');
    } catch (e) {
      _snack('Save failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickAvatar(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      if (picked == null) return;
      setState(() => _avatarBusy = true);
      final url = await _auth.uploadAvatar(File(picked.path));
      if (!mounted) return;
      setState(() => _profile = _profile?.copyWith(avatarUrl: url));
      _snack('Profile picture updated');
    } catch (e) {
      _snack('Upload failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  Future<void> _deleteAvatar() async {
    setState(() => _avatarBusy = true);
    try {
      await _auth.deleteAvatar();
      if (!mounted) return;
      setState(() => _profile = UserProfile(
            id: _profile!.id,
            name: _profile!.name,
            email: _profile!.email,
            role: _profile!.role,
            age: _profile!.age,
            gender: _profile!.gender,
            contactNumber: _profile!.contactNumber,
            location: _profile!.location,
            avatarUrl: null,
          ));
      _snack('Profile picture removed');
    } catch (e) {
      _snack('Delete failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  void _showAvatarOptions() {
    final hasAvatar = (_profile?.avatarUrl ?? '').isNotEmpty;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
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
            if (hasAvatar)
              ListTile(
                leading: Icon(Icons.delete_outline, color: Colors.red.shade400),
                title: Text('Remove photo',
                    style: TextStyle(color: Colors.red.shade400)),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteAvatar();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmSignOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You will need to sign in again to continue.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sign out')),
        ],
      ),
    );
    if (ok == true) await _auth.signOut();
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red.shade700 : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: medsGreen))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildAvatarHeader(),
                const SizedBox(height: 24),
                _SectionLabel('Profile'),
                _Card(
                  child: Column(
                    children: [
                      TextField(
                        controller: _nameCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Full name',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        enabled: false,
                        decoration: InputDecoration(
                          labelText: 'Email',
                          prefixIcon: const Icon(Icons.email_outlined),
                          hintText: _profile?.email ?? '',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _ageCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Age',
                                prefixIcon: Icon(Icons.cake_outlined),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _gender,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Gender',
                                prefixIcon: Icon(Icons.wc_outlined),
                              ),
                              items: _genders
                                  .map((g) => DropdownMenuItem(
                                      value: g, child: Text(g)))
                                  .toList(),
                              onChanged: (v) => setState(() => _gender = v),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _contactCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Contact number',
                          prefixIcon: Icon(Icons.phone_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _locationCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Location',
                          prefixIcon: Icon(Icons.location_on_outlined),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: _saving
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.save_outlined),
                          label: const Text('Save changes'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _SectionLabel('Sensor device'),
                _Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ESP32 heart-rate sensor address. With the sensor on your '
                        'home Wi-Fi, enter the IP shown on its Serial Monitor '
                        '(e.g. 192.168.1.50).',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _sensorCtrl,
                              keyboardType: TextInputType.url,
                              autocorrect: false,
                              decoration: const InputDecoration(
                                labelText: 'Sensor IP or host',
                                prefixIcon: Icon(Icons.router_outlined),
                                hintText: '192.168.1.50',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          FilledButton(
                            onPressed: _saveSensor,
                            child: const Text('Save'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _SectionLabel('Appearance'),
                _Card(child: _buildThemeSelector()),
                const SizedBox(height: 24),
                _Card(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.logout, color: Colors.red.shade400),
                    title: Text('Sign out',
                        style: TextStyle(color: Colors.red.shade400)),
                    onTap: _confirmSignOut,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildAvatarHeader() {
    final url = _profile?.avatarUrl;
    final hasAvatar = url != null && url.isNotEmpty;
    return Center(
      child: Column(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 54,
                backgroundColor: medsGreen.withValues(alpha: 0.15),
                backgroundImage: hasAvatar ? NetworkImage(url) : null,
                child: _avatarBusy
                    ? const CircularProgressIndicator(color: medsGreen)
                    : (!hasAvatar
                        ? const Icon(Icons.person, size: 54, color: medsGreen)
                        : null),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Material(
                  color: medsGreen,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _avatarBusy ? null : _showAvatarOptions,
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.edit, size: 18, color: Colors.black),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _profile?.name?.isNotEmpty == true ? _profile!.name! : 'Your name',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Text(
            _profile?.email ?? '',
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeSelector() {
    return AnimatedBuilder(
      animation: themeController,
      builder: (context, _) => RadioGroup<ThemeMode>(
        groupValue: themeController.mode,
        onChanged: (m) {
          if (m != null) themeController.setMode(m);
        },
        child: const Column(
          children: [
            RadioListTile<ThemeMode>(
              contentPadding: EdgeInsets.zero,
              value: ThemeMode.light,
              secondary: Icon(Icons.light_mode_outlined),
              title: Text('Light'),
            ),
            RadioListTile<ThemeMode>(
              contentPadding: EdgeInsets.zero,
              value: ThemeMode.dark,
              secondary: Icon(Icons.dark_mode_outlined),
              title: Text('Dark'),
            ),
            RadioListTile<ThemeMode>(
              contentPadding: EdgeInsets.zero,
              value: ThemeMode.system,
              secondary: Icon(Icons.brightness_auto_outlined),
              title: Text('System default'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: Colors.grey,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: child,
    );
  }
}
