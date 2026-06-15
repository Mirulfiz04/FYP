import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/detection_session.dart';
import '../../models/user_profile.dart';
import '../../services/admin_service.dart';
import '../sessions_screen.dart';

class AdminSessionsScreen extends StatefulWidget {
  const AdminSessionsScreen({super.key});

  @override
  State<AdminSessionsScreen> createState() => _AdminSessionsScreenState();
}

class _AdminSessionsScreenState extends State<AdminSessionsScreen> {
  final _admin = AdminService();
  List<DetectionSession> _sessions = [];
  Map<String, UserProfile> _users = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final users = await _admin.fetchAllUsers();
      final sessions = await _admin.fetchAllSessions();
      if (mounted) {
        setState(() {
          _users = {for (final u in users) u.id: u};
          _sessions = sessions;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _label(String userId) {
    final u = _users[userId];
    if (u == null) return userId;
    return u.name?.isNotEmpty == true ? u.name! : (u.email ?? userId);
  }

  Color _statusColor(String status) => switch (status) {
        'completed' => const Color(0xFF00DC64),
        'active' => const Color(0xFF00B4FF),
        'cancelled' => const Color(0xFFFF5050),
        _ => Colors.grey,
      };

  String _duration(DetectionSession s) {
    if (s.endTime == null) return 'In progress';
    final d = s.duration;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}h ${m}m' : '${m}m ${sec}s';
  }

  @override
  Widget build(BuildContext context) {
    final active = _sessions.where((s) => s.status == 'active').length;
    return Scaffold(
      appBar: AppBar(
        title: Text('Monitor Sessions  (${_sessions.length})'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF00DC64)))
          : Column(
              children: [
                if (active > 0)
                  Container(
                    width: double.infinity,
                    color: const Color(0xFF00DC64).withValues(alpha: 0.12),
                    padding:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    child: Text('$active session(s) active right now',
                        style: const TextStyle(
                            color: Color(0xFF00A84B),
                            fontWeight: FontWeight.w600)),
                  ),
                Expanded(
                  child: _sessions.isEmpty
                      ? const Center(
                          child: Text('No sessions yet',
                              style: TextStyle(color: Colors.grey)))
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            itemCount: _sessions.length,
                            separatorBuilder: (_, __) => Divider(
                                height: 1,
                                color: Theme.of(context).dividerColor),
                            itemBuilder: (context, i) {
                              final s = _sessions[i];
                              final color = _statusColor(s.status);
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor:
                                      color.withValues(alpha: 0.15),
                                  child: Icon(Icons.person, color: color),
                                ),
                                title: Text(_label(s.userId),
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                                subtitle: Text(
                                  '${DateFormat('dd MMM • HH:mm').format(s.startTime.toLocal())}  ·  ${_duration(s)}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(s.status.toUpperCase(),
                                      style: TextStyle(
                                          color: color,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 10)),
                                ),
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        SessionDetailScreen(session: s),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}
