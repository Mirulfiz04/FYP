import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/detection_session.dart';
import '../../models/emotion_reading.dart';
import '../../models/user_profile.dart';
import '../../services/admin_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/ai_insight_card.dart';
import '../../widgets/ui_kit.dart';

/// Admin "AI Session Summary": pick any user's detection session and get an
/// AI-generated per-session analysis (summary, stress level, trend, tips).
class AdminAiSessionScreen extends StatefulWidget {
  const AdminAiSessionScreen({super.key});

  @override
  State<AdminAiSessionScreen> createState() => _AdminAiSessionScreenState();
}

class _AdminAiSessionScreenState extends State<AdminAiSessionScreen> {
  static const _green = Color(0xFF00DC64);

  final _admin = AdminService();
  final _svc = SupabaseService();

  List<DetectionSession> _sessions = [];
  Map<String, UserProfile> _users = {};
  bool _loading = true;

  DetectionSession? _selected;
  List<EmotionReading> _readings = [];
  bool _readingsLoading = false;

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
      if (!mounted) return;
      setState(() {
        _users = {for (final u in users) u.id: u};
        _sessions = sessions;
        _loading = false;
      });
      if (sessions.isNotEmpty) _select(sessions.first);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _select(DetectionSession s) async {
    setState(() {
      _selected = s;
      _readings = [];
      _readingsLoading = true;
    });
    try {
      final data = await _svc.fetchReadingsForSession(s.sessionId);
      if (mounted && _selected?.sessionId == s.sessionId) {
        setState(() {
          _readings = data;
          _readingsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _readingsLoading = false);
    }
  }

  String _label(String userId) {
    final u = _users[userId];
    if (u == null) return userId;
    return u.name?.isNotEmpty == true ? u.name! : (u.email ?? userId);
  }

  String? _dominant(List<EmotionReading> rs) {
    if (rs.isEmpty) return null;
    final counts = <String, int>{};
    for (final r in rs) {
      counts[r.emotion] = (counts[r.emotion] ?? 0) + 1;
    }
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Session Summary'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _green))
          : _sessions.isEmpty
              ? const Center(
                  child: Text('No sessions yet',
                      style: TextStyle(color: Colors.grey)))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_selected != null) ...[
                      _sessionHeader(_selected!),
                      const SizedBox(height: 16),
                      if (_readingsLoading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 30),
                          child:
                              Center(child: CircularProgressIndicator(color: _green)),
                        )
                      else if (_readings.isEmpty)
                        _infoBanner(
                            'This session has no readings, so there is nothing '
                            'to analyze.')
                      else
                        AiInsightCard(
                          key: ValueKey(_selected!.sessionId),
                          fetchReadings: () async => _readings,
                          title: 'AI SESSION SUMMARY',
                          emptyHint:
                              'Generate an AI summary of how this user felt '
                              'during the session, with trends and tips.',
                          buttonLabel: 'Generate AI Summary',
                        ),
                      const SizedBox(height: 24),
                    ],
                    const Text('CHOOSE A SESSION',
                        style: TextStyle(
                            color: Colors.grey,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            letterSpacing: 1)),
                    const SizedBox(height: 8),
                    ..._sessions.map(_sessionTile),
                  ],
                ),
    );
  }

  Widget _sessionHeader(DetectionSession s) {
    final fmt = DateFormat('dd MMM yyyy • HH:mm');
    final dom = _dominant(_readings);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(
                backgroundColor: Color(0x2200DC64),
                child: Icon(Icons.person, color: _green),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_label(s.userId),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(fmt.format(s.startTime.toLocal()),
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(s.status.toUpperCase(),
                    style: const TextStyle(
                        color: _green,
                        fontWeight: FontWeight.bold,
                        fontSize: 10)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _miniStat('Readings', '${_readings.length}'),
              _miniStat('Dominant', dom ?? '—'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _sessionTile(DetectionSession s) {
    final selected = _selected?.sessionId == s.sessionId;
    final fmt = DateFormat('dd MMM • HH:mm');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? _green : Theme.of(context).dividerColor,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: ListTile(
        onTap: () => _select(s),
        leading: Icon(Icons.event_note_outlined,
            color: selected ? _green : Colors.grey),
        title: Text(_label(s.userId),
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
            '${fmt.format(s.startTime.toLocal())}  ·  ${s.status}',
            style: const TextStyle(fontSize: 12)),
        trailing: selected
            ? const Icon(Icons.check_circle, color: _green)
            : const Icon(Icons.chevron_right, color: Colors.grey),
      ),
    );
  }

  Widget _infoBanner(String text) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Text(text,
          style: const TextStyle(color: Colors.grey, fontSize: 13)),
    );
  }
}
