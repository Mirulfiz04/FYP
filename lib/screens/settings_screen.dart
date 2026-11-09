import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/ble_sensor_service.dart';
import '../services/esp32_sensor_service.dart';
import '../services/sensor_config.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';
import 'notification_settings_screen.dart';

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

  // Sensor "Test connection" state.
  bool _testingSensor = false;
  bool _sensorOk = false;
  String? _sensorStatus; // null until the user runs a test

  // Transport (Wi-Fi vs Bluetooth) + BLE scan/connect state.
  SensorTransport _transport = sensorConfig.transport;
  bool _bleBusy = false;
  bool _bleOk = false;
  String? _bleStatus; // null until the user runs a BLE scan

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

  /// Pings the ESP32 `/data` endpoint at the currently entered address (without
  /// needing to start a session) and reports whether the sensor is reachable.
  Future<void> _testSensor() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _testingSensor = true;
      _sensorStatus = null;
    });
    final url = sensorConfig.normalize(_sensorCtrl.text);
    try {
      final reading = await Esp32SensorService(
        baseUrl: url,
        timeout: const Duration(seconds: 4),
      ).fetchReading();
      if (!mounted) return;
      setState(() {
        _sensorOk = true;
        _sensorStatus = reading.hr > 0
            ? 'Connected to $url\nHR ${reading.hr} bpm · SpO₂ ${reading.spo2}%'
            : 'Connected to $url — but no pulse yet. '
                'Place a finger on the sensor and test again.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sensorOk = false;
        _sensorStatus = 'Could not reach $url\n${_friendlyError(e)}';
      });
    } finally {
      if (mounted) setState(() => _testingSensor = false);
    }
  }

  String _friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('TimeoutException')) {
      return 'Timed out. Make sure the phone is joined to the MEDS_ESP32 '
          'Wi-Fi and the IP above is correct.';
    }
    if (s.contains('SocketException') || s.contains('Failed host lookup')) {
      return 'No route to the sensor. Join the MEDS_ESP32 Wi-Fi (keep mobile '
          'data on for internet).';
    }
    return s;
  }

  void _setTransport(SensorTransport t) {
    setState(() {
      _transport = t;
      // Reset any previous test results when switching transport.
      _sensorStatus = null;
      _bleStatus = null;
    });
    sensorConfig.setTransport(t);
  }

  /// Scans for the MEDS_ESP32 over Bluetooth LE, connects, and reads one sample.
  /// Remembers the device so live sessions reconnect to it directly.
  Future<void> _scanAndConnectBle() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _bleBusy = true;
      _bleStatus = null;
    });
    try {
      final ble = BleSensorService.instance;
      await ble.connect();
      final reading = await ble.fetchReading();
      final id = ble.connectedDeviceId;
      final name = ble.connectedDeviceName;
      if (id != null) {
        await sensorConfig.setBleDevice(id: id, name: name);
      }
      if (!mounted) return;
      final label = (name != null && name.isNotEmpty) ? name : (id ?? 'sensor');
      setState(() {
        _bleOk = true;
        _bleStatus = reading.hr > 0
            ? 'Connected to $label\nHR ${reading.hr} bpm · SpO₂ ${reading.spo2}%'
            : 'Connected to $label — but no pulse yet. Place a finger on the '
                'sensor and test again.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bleOk = false;
        _bleStatus = _bleError(e);
      });
    } finally {
      if (mounted) setState(() => _bleBusy = false);
    }
  }

  String _bleError(Object e) {
    final s = e.toString();
    if (s.contains('not available') || s.contains('not supported')) {
      return 'Bluetooth unavailable. BLE does not work on the Android '
          'emulator — run on a physical phone over USB.';
    }
    if (s.contains('permission')) {
      return 'Bluetooth permission denied. Allow Nearby devices in app '
          'settings and try again.';
    }
    if (s.contains('find') || s.contains('TimeoutException')) {
      return 'Could not find MEDS_ESP32. Make sure the ESP32 is powered, '
          'running the BLE firmware, and Bluetooth is on.';
    }
    return s;
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
                const SectionHeader(
                  title: 'Profile',
                  icon: Icons.badge_outlined,
                  color: MedsColors.blue,
                ),
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
                const SectionHeader(
                  title: 'Sensor device',
                  icon: Icons.router_outlined,
                  color: MedsColors.teal,
                ),
                _buildSensorCard(),
                const SizedBox(height: 24),
                const SectionHeader(
                  title: 'Appearance',
                  icon: Icons.palette_outlined,
                  color: MedsColors.purple,
                ),
                _Card(child: _buildThemeSelector()),
                const SizedBox(height: 24),
                const SectionHeader(
                  title: 'Notifications',
                  icon: Icons.notifications_outlined,
                  color: MedsColors.amber,
                ),
                _Card(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.tune, color: MedsColors.amber),
                    title: const Text('Notification settings'),
                    subtitle:
                        const Text('Choose which alerts you receive'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const NotificationSettingsScreen()),
                    ),
                  ),
                ),
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

  Widget _buildSensorCard() {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<SensorTransport>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: SensorTransport.wifi,
                label: Text('Wi-Fi'),
              ),
              ButtonSegment(
                value: SensorTransport.ble,
                label: Text('Bluetooth'),
              ),
              ButtonSegment(
                value: SensorTransport.simulated,
                label: Text('Simulated'),
              ),
            ],
            selected: {_transport},
            onSelectionChanged: (s) => _setTransport(s.first),
          ),
          const SizedBox(height: 16),
          if (_transport == SensorTransport.wifi)
            ..._buildWifiSensor()
          else if (_transport == SensorTransport.ble)
            ..._buildBleSensor()
          else
            ..._buildSimulatedSensor(),
        ],
      ),
    );
  }

  List<Widget> _buildWifiSensor() {
    return [
      const Text(
        'ESP32 heart-rate sensor address. With the sensor on your home Wi-Fi, '
        'enter the IP shown on its Serial Monitor (e.g. 192.168.1.50).',
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
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _testingSensor ? null : _testSensor,
          icon: _testingSensor
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.wifi_tethering),
          label: Text(_testingSensor ? 'Testing…' : 'Test connection'),
        ),
      ),
      if (_sensorStatus != null) ...[
        const SizedBox(height: 12),
        _statusBox(_sensorOk, _sensorStatus!),
      ],
    ];
  }

  List<Widget> _buildBleSensor() {
    return [
      const Text(
        'Connect to the ESP32 over Bluetooth LE. The phone keeps its normal '
        'Wi-Fi/internet, so no mobile-data workaround is needed. Requires a '
        'physical phone — Bluetooth does not work on the emulator.',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      ),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _bleBusy ? null : _scanAndConnectBle,
          icon: _bleBusy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.bluetooth_searching),
          label: Text(_bleBusy ? 'Scanning…' : 'Scan & connect'),
        ),
      ),
      if (sensorConfig.bleDeviceName != null ||
          sensorConfig.bleDeviceId != null) ...[
        const SizedBox(height: 10),
        Text(
          'Saved device: '
          '${sensorConfig.bleDeviceName ?? sensorConfig.bleDeviceId}',
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ],
      if (_bleStatus != null) ...[
        const SizedBox(height: 12),
        _statusBox(_bleOk, _bleStatus!),
      ],
      const SizedBox(height: 12),
      const _BleDebugPanel(),
    ];
  }

  List<Widget> _buildSimulatedSensor() {
    return [
      const Text(
        'Generates realistic fake heart-rate data — no hardware needed. Use '
        'this to demo or develop the full flow on the Android emulator, where '
        'real Wi-Fi/Bluetooth sensors can\'t connect. Live sessions, baseline '
        'and AI insights all run on the simulated numbers.',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      ),
      const SizedBox(height: 12),
      _statusBox(true, 'Simulated sensor active — start a session to see live '
          'readings (~70 bpm).'),
    ];
  }

  Widget _statusBox(bool ok, String text) {
    final color = ok ? MedsColors.green : MedsColors.red;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ok ? Icons.check_circle : Icons.error_outline,
              color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 12.5)),
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

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) => AppCard(child: child);
}

/// Live BLE diagnostics for hardware bring-up: connection state, frame count,
/// time since the last notification, and the raw frame text — so a truncated or
/// malformed frame (e.g. MTU too small) is obvious at a glance.
class _BleDebugPanel extends StatefulWidget {
  const _BleDebugPanel();

  @override
  State<_BleDebugPanel> createState() => _BleDebugPanelState();
}

class _BleDebugPanelState extends State<_BleDebugPanel> {
  final _ble = BleSensorService.instance;
  StreamSubscription<String>? _frameSub;
  StreamSubscription<bool>? _connSub;
  Timer? _ageTimer;

  @override
  void initState() {
    super.initState();
    _frameSub = _ble.rawFrames.listen((_) {
      if (mounted) setState(() {});
    });
    _connSub = _ble.connectionState.listen((_) {
      if (mounted) setState(() {});
    });
    // Refresh the "last frame N s ago" line even when no frames arrive.
    _ageTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _frameSub?.cancel();
    _connSub?.cancel();
    _ageTimer?.cancel();
    super.dispose();
  }

  bool _isJson(String s) {
    try {
      json.decode(s);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = _ble.isConnected;
    final raw = _ble.lastRawFrame;
    final at = _ble.lastFrameAt;
    final ageSecs = at == null ? null : DateTime.now().difference(at).inSeconds;
    final parses = raw != null && _isJson(raw);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bug_report_outlined,
                  size: 16, color: MedsColors.muted),
              const SizedBox(width: 6),
              const Text('BLE debug',
                  style:
                      TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
              const Spacer(),
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: connected ? MedsColors.green : MedsColors.muted,
                ),
              ),
              const SizedBox(width: 6),
              Text(connected ? 'Connected' : 'Not connected',
                  style: const TextStyle(fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          _line('Device',
              _ble.connectedDeviceName ?? _ble.connectedDeviceId ?? '—'),
          _line('Frames', '${_ble.framesReceived}'),
          _line('Last frame', ageSecs == null ? '—' : '${ageSecs}s ago'),
          const SizedBox(height: 8),
          const Text('Raw frame',
              style: TextStyle(fontSize: 11, color: MedsColors.muted)),
          const SizedBox(height: 2),
          SelectableText(
            raw ?? '(no notifications yet)',
            style: const TextStyle(
                fontFamily: 'monospace', fontSize: 11.5, height: 1.3),
          ),
          if (raw != null && !parses) ...[
            const SizedBox(height: 6),
            const Text(
              '⚠ Frame is not valid JSON — likely MTU truncation. Check '
              'NimBLEDevice::setMTU(247) on the ESP32.',
              style: TextStyle(fontSize: 11, color: MedsColors.red),
            ),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: connected ? () => _ble.disconnect() : null,
              icon: const Icon(Icons.link_off, size: 16),
              label: const Text('Disconnect'),
              style: TextButton.styleFrom(
                foregroundColor: MedsColors.red,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _line(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style:
                    const TextStyle(fontSize: 12, color: MedsColors.muted)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
