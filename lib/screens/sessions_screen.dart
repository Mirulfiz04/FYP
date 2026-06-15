import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/detection_session.dart';
import '../models/emotion_reading.dart';
import '../services/supabase_service.dart';

class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key});

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  final _svc = SupabaseService();
  List<DetectionSession> _sessions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _svc.fetchSessions();
      if (mounted) {
        setState(() {
          _sessions = data;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('My Sessions  (${_sessions.length})'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00DC64)))
          : _sessions.isEmpty
              ? const Center(
                  child: Text(
                    'No sessions yet.\nStart one from the Home tab.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 15),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    itemCount: _sessions.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: Theme.of(context).dividerColor),
                    itemBuilder: (context, i) =>
                        _SessionTile(session: _sessions[i]),
                  ),
                ),
    );
  }
}

String _fmtDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '${h}h ${m}m ${s}s' : '${m}m ${s}s';
}

Color _statusColor(String status) => switch (status) {
      'completed' => const Color(0xFF00DC64),
      'active' => const Color(0xFF00B4FF),
      'cancelled' => const Color(0xFFFF5050),
      _ => Colors.grey,
    };

class _SessionTile extends StatelessWidget {
  final DetectionSession session;
  const _SessionTile({required this.session});

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(session.status);
    final started =
        DateFormat('dd MMM yyyy • HH:mm').format(session.startTime.toLocal());
    final durationText =
        session.endTime != null ? _fmtDuration(session.duration) : 'In progress';

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.15),
        child: Icon(Icons.psychology, color: color),
      ),
      title: Text(started, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('Duration: $durationText',
          style: const TextStyle(color: Colors.grey, fontSize: 12)),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          session.status.toUpperCase(),
          style: TextStyle(
              color: color, fontWeight: FontWeight.bold, fontSize: 10),
        ),
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => SessionDetailScreen(session: session)),
      ),
    );
  }
}

class SessionDetailScreen extends StatefulWidget {
  final DetectionSession session;
  const SessionDetailScreen({super.key, required this.session});

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  final _svc = SupabaseService();
  List<EmotionReading> _readings = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _svc.fetchReadingsForSession(widget.session.sessionId);
      if (mounted) {
        setState(() {
          _readings = data;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  MapEntry<String, int>? get _dominant {
    if (_readings.isEmpty) return null;
    final counts = <String, int>{};
    for (final r in _readings) {
      counts[r.emotion] = (counts[r.emotion] ?? 0) + 1;
    }
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final fmt = DateFormat('dd MMM yyyy • HH:mm:ss');
    final color = _statusColor(s.status);

    return Scaffold(
      appBar: AppBar(title: const Text('Session details')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00DC64)))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _DetailCard(children: [
                  _DetailRow(
                    label: 'Status',
                    valueWidget: Text(
                      s.status.toUpperCase(),
                      style: TextStyle(
                          color: color, fontWeight: FontWeight.bold),
                    ),
                  ),
                  _DetailRow(label: 'Started', value: fmt.format(s.startTime.toLocal())),
                  _DetailRow(
                    label: 'Ended',
                    value: s.endTime != null
                        ? fmt.format(s.endTime!.toLocal())
                        : '—',
                  ),
                  _DetailRow(
                    label: 'Duration',
                    value: s.endTime != null
                        ? _fmtDuration(s.duration)
                        : 'In progress',
                  ),
                  if (s.notes != null && s.notes!.isNotEmpty)
                    _DetailRow(label: 'Notes', value: s.notes!),
                ]),
                const SizedBox(height: 16),
                _DetailCard(children: [
                  _DetailRow(label: 'Readings captured', value: '${_readings.length}'),
                  _DetailRow(
                    label: 'Most frequent emotion',
                    value: _dominant != null
                        ? '${_dominant!.key}  (${_dominant!.value})'
                        : '—',
                  ),
                ]),
                const SizedBox(height: 16),
                if (_readings.isNotEmpty) ...[
                  const Text('READINGS',
                      style: TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1)),
                  const SizedBox(height: 8),
                  ..._readings.map((r) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.face_retouching_natural,
                            size: 20, color: Colors.grey),
                        title: Text(
                            '${r.emotion}  ·  ${r.confidence.toStringAsFixed(0)}%'),
                        subtitle: Text(
                          'HR ${r.hr > 0 ? '${r.hr} bpm' : '—'}   SpO2 ${r.spo2 > 0 ? '${r.spo2}%' : '—'}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: Text(
                          DateFormat('HH:mm:ss').format(r.createdAt.toLocal()),
                          style:
                              const TextStyle(color: Colors.grey, fontSize: 11),
                        ),
                      )),
                ],
              ],
            ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  final List<Widget> children;
  const _DetailCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(children: children),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String? value;
  final Widget? valueWidget;

  const _DetailRow({required this.label, this.value, this.valueWidget});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(width: 12),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: valueWidget ??
                  Text(value ?? '',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}
