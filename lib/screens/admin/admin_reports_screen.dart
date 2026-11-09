import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../models/detection_session.dart';
import '../../models/emotion_reading.dart';
import '../../models/user_profile.dart';
import '../../services/admin_service.dart';
import '../../widgets/ui_kit.dart';

class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  final _admin = AdminService();

  bool _loading = true;
  String _summary = '';
  String _sessionsCsv = '';

  @override
  void initState() {
    super.initState();
    _build();
  }

  Future<void> _build() async {
    setState(() => _loading = true);
    try {
      final users = await _admin.fetchAllUsers();
      final sessions = await _admin.fetchAllSessions();
      final readings = await _admin.fetchRecentReadings();
      int totalReadings;
      try {
        totalReadings = await _admin.countRows('emotion_readings');
      } catch (_) {
        totalReadings = readings.length;
      }
      _summary = _buildSummary(users, sessions, readings, totalReadings);
      _sessionsCsv = _buildSessionsCsv(users, sessions);
    } catch (e) {
      _summary = 'Failed to build report: $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _buildSummary(
    List<UserProfile> users,
    List<DetectionSession> sessions,
    List<EmotionReading> readings,
    int totalReadings,
  ) {
    final now = DateFormat('dd MMM yyyy HH:mm').format(DateTime.now());
    final admins = users.where((u) => u.isAdmin).length;
    final blocked = users.where((u) => u.isBlocked).length;
    final active = sessions.where((s) => s.status == 'active').length;
    final completed = sessions.where((s) => s.status == 'completed').length;

    final completedSessions =
        sessions.where((s) => s.endTime != null).toList();
    var avg = Duration.zero;
    if (completedSessions.isNotEmpty) {
      final secs = completedSessions.fold<int>(
          0, (a, s) => a + s.duration.inSeconds);
      avg = Duration(seconds: (secs / completedSessions.length).round());
    }

    final counts = <String, int>{};
    for (final r in readings) {
      counts[r.emotion] = (counts[r.emotion] ?? 0) + 1;
    }
    final emotionLines = (counts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .map((e) => '  - ${e.key}: ${e.value}')
        .join('\n');

    return '''
MEDS — SYSTEM REPORT
Generated: $now

USERS
  Total users : ${users.length}
  Admins      : $admins
  Blocked     : $blocked

SESSIONS
  Total       : ${sessions.length}
  Active      : $active
  Completed   : $completed
  Avg length  : ${_fmtDuration(avg)}

READINGS
  Total       : $totalReadings
  Emotion breakdown (latest ${readings.length}):
${emotionLines.isEmpty ? '  - none' : emotionLines}
''';
  }

  String _buildSessionsCsv(
    List<UserProfile> users,
    List<DetectionSession> sessions,
  ) {
    final byId = {for (final u in users) u.id: u};
    final rows = <String>[
      'session_id,user_name,user_email,start_time,end_time,status,duration_seconds',
    ];
    for (final s in sessions) {
      final u = byId[s.userId];
      final duration = s.endTime != null ? s.duration.inSeconds.toString() : '';
      rows.add([
        s.sessionId,
        u?.name ?? '',
        u?.email ?? '',
        s.startTime.toIso8601String(),
        s.endTime?.toIso8601String() ?? '',
        s.status,
        duration,
      ].map(_csv).join(','));
    }
    return rows.join('\n');
  }

  String _csv(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  String _fmtDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}h ${m}m ${s}s' : '${m}m ${s}s';
  }

  Future<void> _copy(String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$what copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Generate Reports'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _build),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF00DC64)))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _copy(_summary, 'Summary'),
                        icon: const Icon(Icons.copy_all_outlined),
                        label: const Text('Copy summary'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _copy(_sessionsCsv, 'Sessions CSV'),
                        icon: const Icon(Icons.table_view_outlined),
                        label: const Text('Copy CSV'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Paste the CSV into Excel or Google Sheets to save it as a file.',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 16),
                AppCard(
                  child: SelectableText(
                    _summary,
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 12.5, height: 1.4),
                  ),
                ),
              ],
            ),
    );
  }
}
