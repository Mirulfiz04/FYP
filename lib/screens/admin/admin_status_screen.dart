import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/admin_service.dart';
import '../../services/esp32_sensor_service.dart';

enum _Health { checking, ok, warn, fail }

class _Check {
  _Health health;
  String detail;
  _Check(this.health, this.detail);
}

class AdminStatusScreen extends StatefulWidget {
  const AdminStatusScreen({super.key});

  @override
  State<AdminStatusScreen> createState() => _AdminStatusScreenState();
}

class _AdminStatusScreenState extends State<AdminStatusScreen> {
  final _admin = AdminService();
  final _client = Supabase.instance.client;

  final _database = _Check(_Health.checking, 'Checking…');
  final _sessionsTable = _Check(_Health.checking, 'Checking…');
  final _readingsTable = _Check(_Health.checking, 'Checking…');
  final _auth = _Check(_Health.checking, 'Checking…');
  final _storage = _Check(_Health.checking, 'Checking…');
  final _sensor = _Check(_Health.checking, 'Checking…');

  DateTime? _lastChecked;

  @override
  void initState() {
    super.initState();
    _runAll();
  }

  Future<void> _runAll() async {
    _reset();
    await Future.wait([
      _checkProfiles(),
      _checkSessions(),
      _checkReadings(),
      _checkAuth(),
      _checkStorage(),
      _checkSensor(),
    ]);
    if (mounted) setState(() => _lastChecked = DateTime.now());
  }

  void _reset() {
    for (final c in [
      _database,
      _sessionsTable,
      _readingsTable,
      _auth,
      _storage,
      _sensor
    ]) {
      c.health = _Health.checking;
      c.detail = 'Checking…';
    }
    setState(() {});
  }

  Future<void> _checkProfiles() async {
    try {
      final n = await _admin.countRows('profiles');
      _set(_database, _Health.ok, 'Connected · $n profiles');
    } catch (e) {
      _set(_database, _Health.fail, 'Query failed: $e');
    }
  }

  Future<void> _checkSessions() async {
    try {
      final n = await _admin.countRows('detection_sessions');
      _set(_sessionsTable, _Health.ok, '$n sessions');
    } catch (e) {
      _set(_sessionsTable, _Health.fail, 'Missing or unreadable: run sessions SQL');
    }
  }

  Future<void> _checkReadings() async {
    try {
      final n = await _admin.countRows('emotion_readings');
      _set(_readingsTable, _Health.ok, '$n readings');
    } catch (e) {
      _set(_readingsTable, _Health.fail, 'Query failed: $e');
    }
  }

  Future<void> _checkAuth() async {
    final user = _client.auth.currentUser;
    if (user != null) {
      _set(_auth, _Health.ok, 'Signed in as ${user.email ?? user.id}');
    } else {
      _set(_auth, _Health.fail, 'No active session');
    }
  }

  Future<void> _checkStorage() async {
    try {
      await _client.storage.from('avatars').list();
      _set(_storage, _Health.ok, "Bucket 'avatars' reachable");
    } catch (e) {
      _set(_storage, _Health.warn, "Bucket 'avatars' not reachable");
    }
  }

  Future<void> _checkSensor() async {
    try {
      final r = await Esp32SensorService().fetchReading();
      _set(_sensor, _Health.ok, 'Online · HR ${r.hr} bpm');
    } catch (_) {
      _set(_sensor, _Health.warn, 'Offline (optional hardware)');
    }
  }

  void _set(_Check c, _Health h, String detail) {
    if (!mounted) return;
    setState(() {
      c.health = h;
      c.detail = detail;
    });
  }

  @override
  Widget build(BuildContext context) {
    final checks = <(String, IconData, _Check)>[
      ('Database connection', Icons.dns_outlined, _database),
      ('Sessions table', Icons.event_note_outlined, _sessionsTable),
      ('Readings table', Icons.insights_outlined, _readingsTable),
      ('Authentication', Icons.lock_outline, _auth),
      ('Storage (avatars)', Icons.folder_outlined, _storage),
      ('ESP32 sensor', Icons.bluetooth_connected, _sensor),
    ];

    final allOk = checks.every((c) => c.$3.health == _Health.ok);
    final anyFail = checks.any((c) => c.$3.health == _Health.fail);
    final overall = anyFail
        ? (const Color(0xFFFF5050), 'Issues detected', Icons.error_outline)
        : allOk
            ? (const Color(0xFF00DC64), 'All systems operational',
                Icons.check_circle_outline)
            : (const Color(0xFFFFA500), 'Running with warnings',
                Icons.warning_amber_rounded);

    return Scaffold(
      appBar: AppBar(
        title: const Text('System Status'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _runAll),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: overall.$1.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: overall.$1.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Icon(overall.$3, color: overall.$1, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(overall.$2,
                          style: TextStyle(
                              color: overall.$1,
                              fontWeight: FontWeight.bold,
                              fontSize: 16)),
                      if (_lastChecked != null)
                        Text(
                          'Last checked ${DateFormat('HH:mm:ss').format(_lastChecked!)}',
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 12),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ...checks.map((c) => _CheckRow(
                title: c.$1,
                icon: c.$2,
                check: c.$3,
              )),
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  final String title;
  final IconData icon;
  final _Check check;

  const _CheckRow({
    required this.title,
    required this.icon,
    required this.check,
  });

  Widget _trailing() {
    switch (check.health) {
      case _Health.checking:
        return const SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(strokeWidth: 2));
      case _Health.ok:
        return const Icon(Icons.check_circle, color: Color(0xFF00DC64));
      case _Health.warn:
        return const Icon(Icons.warning_amber_rounded,
            color: Color(0xFFFFA500));
      case _Health.fail:
        return const Icon(Icons.cancel, color: Color(0xFFFF5050));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(check.detail,
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _trailing(),
        ],
      ),
    );
  }
}
