import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/emotion_reading.dart';
import '../services/auth_service.dart';
import '../services/data_export_service.dart';
import '../services/export_history_service.dart';
import '../services/session_details_service.dart';
import '../theme/app_theme.dart';
import '../viewmodels/session_details_controller.dart';
import '../widgets/email_export_sheet.dart';
import '../widgets/emotion_distribution_card.dart';
import '../widgets/heart_rate_chart.dart';
import '../widgets/recent_readings_card.dart';
import '../widgets/session_ai_summary_card.dart';
import '../widgets/session_data_quality_card.dart';
import '../widgets/session_metric_cards.dart';
import '../widgets/session_summary_card.dart';
import '../widgets/ui_kit.dart';

const Color _accent = Color(0xFF6A5AE0);

enum _MenuAction { email, export, review, delete }

/// Session Details dashboard. Loads everything by [sessionId] (no hard-coded
/// data); analytics are computed in the service, not here.
class SessionDetailsPage extends StatefulWidget {
  final String sessionId;
  final bool scrollToAi;

  const SessionDetailsPage({
    super.key,
    required this.sessionId,
    this.scrollToAi = false,
  });

  @override
  State<SessionDetailsPage> createState() => _SessionDetailsPageState();
}

class _SessionDetailsPageState extends State<SessionDetailsPage> {
  late final SessionDetailsController _c = SessionDetailsController(
    service: SupabaseSessionDetailsService(),
    sessionId: widget.sessionId,
  );
  final _aiKey = GlobalKey();
  Future<ExportRecord?>? _lastExport;

  @override
  void initState() {
    super.initState();
    _c.load().then((_) => _maybeScrollToAi());
    _refreshLastExport();
  }

  void _refreshLastExport() {
    if (!mounted) return;
    setState(() {
      _lastExport = ExportHistoryService().lastForSession(widget.sessionId);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _maybeScrollToAi() {
    if (!widget.scrollToAi || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _aiKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx,
            duration: const Duration(milliseconds: 400), alignment: 0.1);
      }
    });
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  void _copyReport() {
    Clipboard.setData(ClipboardData(text: _c.reportText()));
    _snack('Report copied to clipboard');
  }

  Future<void> _emailSession() async {
    final d = _c.data;
    if (d == null) return;
    final myEmail = AuthService().currentUser?.email;
    final dateLabel = DateFormat('dd MMM yyyy').format(d.session.startTime.toLocal());
    final sent = await showEmailExportSheet(
      context,
      title: 'Email this session',
      subject: 'MEDS session report — $dateLabel',
      myEmail: myEmail,
      historyScope: 'session',
      historySessionId: widget.sessionId,
      builder: ({required bool includeCsv, required bool includePdf}) =>
          DataExportService().buildSessionExport(
        session: d.session,
        readings: d.readings,
        analytics: d.analytics,
        userName: d.viewerIsAdmin ? d.userName : null,
        includeCsv: includeCsv,
        includePdf: includePdf,
      ),
    );
    if (sent) _refreshLastExport();
  }

  /// Subtle "you already exported this" line, shown when a record exists.
  Widget _lastExportNote() {
    return FutureBuilder<ExportRecord?>(
      future: _lastExport,
      builder: (context, snap) {
        final r = snap.data;
        if (r == null) return const SizedBox.shrink();
        final when = DateFormat('d MMM yyyy, h:mm a').format(r.sentAt.toLocal());
        final what = r.method == 'file'
            ? 'Shared as file'
            : 'Emailed to ${r.recipient}';
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(children: [
            const Icon(Icons.history, size: 15, color: MedsColors.muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text('$what · $when',
                  style: const TextStyle(
                      color: MedsColors.muted, fontSize: 12.5)),
            ),
          ]),
        );
      },
    );
  }

  Future<void> _markReview() async {
    final ok = await _c.toggleReview();
    _snack(ok
        ? (_c.flaggedForReview ? 'Marked for review' : 'Review flag removed')
        : 'Could not update review status');
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete session?'),
        content: const Text(
            'This permanently removes the session and its readings. This '
            'cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: MedsColors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final done = await _c.deleteSession();
    if (!mounted) return;
    if (done) {
      Navigator.of(context).pop(true);
    } else {
      _snack('Could not delete the session.');
    }
  }

  void _openFullLogs() {
    final readings = _c.data?.readings ?? const [];
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SessionFullLogsPage(readings: readings),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Session Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.mark_email_read_outlined),
            tooltip: 'Email this session',
            onPressed: _c.data == null ? null : _emailSession,
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Copy summary',
            onPressed: _c.data == null ? null : _copyReport,
          ),
          PopupMenuButton<_MenuAction>(
            onSelected: (a) => switch (a) {
              _MenuAction.email => _emailSession(),
              _MenuAction.export => _copyReport(),
              _MenuAction.review => _markReview(),
              _MenuAction.delete => _delete(),
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                  value: _MenuAction.email,
                  child: Text('Email / export data')),
              const PopupMenuItem(
                  value: _MenuAction.export,
                  child: Text('Copy report')),
              PopupMenuItem(
                  value: _MenuAction.review,
                  child: Text(_c.flaggedForReview
                      ? 'Remove review flag'
                      : 'Mark for review')),
              if (_c.isAdmin)
                const PopupMenuItem(
                    value: _MenuAction.delete,
                    child: Text('Delete session')),
            ],
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _c,
        builder: (context, _) {
          if (_c.loading && _c.data == null) return _skeleton();
          if (_c.error != null || _c.data == null) {
            return Center(
              child: EmptyState(
                icon: Icons.error_outline,
                title: 'Could not load this session',
                message: 'Please check your connection and try again.',
                color: MedsColors.red,
                action: FilledButton.icon(
                  onPressed: _c.refresh,
                  style: FilledButton.styleFrom(backgroundColor: _accent),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try Again'),
                ),
              ),
            );
          }
          return _content();
        },
      ),
      bottomNavigationBar: ListenableBuilder(
        listenable: _c,
        builder: (context, _) =>
            _c.data == null ? const SizedBox.shrink() : _bottomBar(),
      ),
    );
  }

  Widget _content() {
    final d = _c.data!;
    final a = d.analytics;
    return RefreshIndicator(
      onRefresh: _c.refresh,
      color: _accent,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _lastExportNote(),
          SessionSummaryCard(
            session: d.session,
            userName: d.userName,
            showUser: d.viewerIsAdmin, // user shown to administrators
          ),
          const SizedBox(height: 14),
          SessionMetricCards(analytics: a),
          const SizedBox(height: 14),
          HeartRateChart(analytics: a),
          const SizedBox(height: 14),
          EmotionDistributionCard(
            distribution: a.distribution,
            totalReadings: a.totalReadings,
            onViewDetails: _openFullLogs,
          ),
          const SizedBox(height: 14),
          Container(
              key: _aiKey, child: SessionAiSummaryCard(session: d.session)),
          const SizedBox(height: 14),
          RecentReadingsCard(
            readings: a.recent,
            onViewFullLogs: _openFullLogs,
          ),
          const SizedBox(height: 14),
          SessionDataQualityCard(analytics: a),
        ],
      ),
    );
  }

  Widget _bottomBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _copyReport,
                style: OutlinedButton.styleFrom(
                    foregroundColor: _accent,
                    padding: const EdgeInsets.symmetric(vertical: 12)),
                icon: const Icon(Icons.ios_share, size: 18),
                label: const Text('Export', style: TextStyle(fontSize: 12.5)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _openFullLogs,
                style: OutlinedButton.styleFrom(
                    foregroundColor: _accent,
                    padding: const EdgeInsets.symmetric(vertical: 12)),
                icon: const Icon(Icons.list_alt, size: 18),
                label: const Text('Full Logs', style: TextStyle(fontSize: 12.5)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: _c.busy ? null : _markReview,
                style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    padding: const EdgeInsets.symmetric(vertical: 12)),
                icon: Icon(
                    _c.flaggedForReview ? Icons.bookmark : Icons.bookmark_border,
                    size: 18),
                label: Text(_c.flaggedForReview ? 'Reviewed' : 'Review',
                    style: const TextStyle(fontSize: 12.5)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _skeleton() {
    Widget box(double h) => Container(
          height: h,
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: MedsColors.muted.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(16),
          ),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [box(150), box(90), box(200), box(180), box(150)],
    );
  }
}

/// Full readings log (all readings, lazy-loaded), opened from "View full logs".
class SessionFullLogsPage extends StatelessWidget {
  final List<EmotionReading> readings;
  const SessionFullLogsPage({super.key, required this.readings});

  static const _validHr = {'GOOD', 'HOLDING HR'};

  @override
  Widget build(BuildContext context) {
    // Newest first for the log view.
    final items = readings.reversed.toList();
    return Scaffold(
      appBar: AppBar(title: Text('Full Logs (${items.length})')),
      body: items.isEmpty
          ? const Center(
              child: Text('No readings for this session.',
                  style: TextStyle(color: MedsColors.muted)))
          : ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: Theme.of(context).dividerColor),
              itemBuilder: (context, i) {
                final r = items[i];
                final color = MedsColors.emotion(r.emotion);
                final validHr = r.hr > 0 && _validHr.contains(r.sensorQuality);
                final validSpo2 = r.spo2 > 0;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.18),
                    child: Text(MedsColors.emoji(r.emotion)),
                  ),
                  title: Text('${r.emotion}  ·  ${r.confidence.round()}%',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    'HR ${validHr ? '${r.hr} bpm' : 'Not available'}   '
                    'SpO₂ ${validSpo2 ? '${r.spo2}%' : 'Not available'}   ·   '
                    '${r.sensorQuality}',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  trailing: Text(
                    DateFormat('HH:mm:ss').format(r.createdAt.toLocal()),
                    style: const TextStyle(
                        color: MedsColors.muted, fontSize: 11.5),
                  ),
                );
              },
            ),
    );
  }
}
