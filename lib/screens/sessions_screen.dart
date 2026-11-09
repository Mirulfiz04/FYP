import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/detection_session.dart';
import '../models/emotion_reading.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/session_ai_summary_card.dart';
import '../widgets/ui_kit.dart';

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
              ? const EmptyState(
                  icon: Icons.event_note_outlined,
                  title: 'No sessions yet',
                  message: 'Start your first detection session from the Home '
                      'tab and it will show up here.',
                  color: MedsColors.blue,
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _sessions.length,
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
              builder: (_) => SessionDetailScreen(session: session)),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(Icons.psychology, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(started,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14.5)),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(Icons.schedule,
                          size: 13, color: MedsColors.muted),
                      const SizedBox(width: 4),
                      Text(durationText,
                          style: const TextStyle(
                              color: MedsColors.muted, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
            Pill(text: session.status.toUpperCase(), color: color),
          ],
        ),
      ),
    );
  }
}

class SessionDetailScreen extends StatefulWidget {
  final DetectionSession session;

  /// When true (e.g. opened from an "AI insight ready" notification), the view
  /// scrolls to the AI Summary section after loading.
  final bool scrollToAi;

  const SessionDetailScreen({
    super.key,
    required this.session,
    this.scrollToAi = false,
  });

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  final _svc = SupabaseService();
  final _aiKey = GlobalKey();
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
        _maybeScrollToAi();
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _maybeScrollToAi() {
    if (!widget.scrollToAi) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _aiKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx,
            duration: const Duration(milliseconds: 400), alignment: 0.1);
      }
    });
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
                Container(
                  key: _aiKey,
                  child: SessionAiSummaryCard(session: widget.session),
                ),
                if (_readings.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const SectionHeader(
                    title: 'Readings',
                    icon: Icons.list_alt,
                    color: MedsColors.blue,
                  ),
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
  Widget build(BuildContext context) =>
      AppCard(child: Column(children: children));
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

/// Loads a session by id then shows [SessionDetailScreen]. Used by notification
/// deep links, which only carry the `sessionId`.
class SessionDetailLoaderScreen extends StatefulWidget {
  final String sessionId;
  final bool scrollToAi;

  const SessionDetailLoaderScreen({
    super.key,
    required this.sessionId,
    this.scrollToAi = false,
  });

  @override
  State<SessionDetailLoaderScreen> createState() =>
      _SessionDetailLoaderScreenState();
}

class _SessionDetailLoaderScreenState extends State<SessionDetailLoaderScreen> {
  final _svc = SupabaseService();
  DetectionSession? _session;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await _svc.fetchSession(widget.sessionId);
      if (mounted) setState(() => _session = s);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not open session: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Session details')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_error!, textAlign: TextAlign.center),
          ),
        ),
      );
    }
    if (_session == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Color(0xFF00DC64))),
      );
    }
    return SessionDetailScreen(
      session: _session!,
      scrollToAi: widget.scrollToAi,
    );
  }
}
