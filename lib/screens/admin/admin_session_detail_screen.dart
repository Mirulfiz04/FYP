import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../models/admin_session_detail.dart';
import '../../models/admin_sessions_model.dart';
import '../../models/detection_session.dart';
import '../../models/emotion_reading.dart';
import '../../models/session_liveness.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/admin/admin_header.dart';
import '../../widgets/admin/hr_trend_chart.dart';
import '../../widgets/admin/monitor_session_card.dart' show sessionStatusColor;
import '../../widgets/ui_kit.dart';
import '../emotion_analytics_screen.dart';

/// Admin "Session Details" — a rich, read-only view of one monitoring session.
/// Opened (pushed) from Monitor Sessions / the dashboard / insights. Distinct
/// from the user-facing `SessionDetailScreen`, which is left unchanged.
class AdminSessionDetailScreen extends StatefulWidget {
  final DetectionSession session;
  final String userName;
  final String? avatarUrl;
  final String? initials;

  /// Injected in tests; defaults to the Supabase-backed session readings query.
  final Future<List<EmotionReading>> Function(String sessionId)? readingsLoader;

  const AdminSessionDetailScreen({
    super.key,
    required this.session,
    required this.userName,
    this.avatarUrl,
    this.initials,
    this.readingsLoader,
  });

  @override
  State<AdminSessionDetailScreen> createState() =>
      _AdminSessionDetailScreenState();
}

class _AdminSessionDetailScreenState extends State<AdminSessionDetailScreen> {
  late final _loadReadings = widget.readingsLoader ??
      (String id) => SupabaseService().fetchReadingsForSession(id);

  SessionDetailData? _data;
  List<EmotionReading> _readings = const [];
  bool _loading = true;
  Object? _error;
  bool _flagged = false;

  DetectionSession get _s => widget.session;

  /// Display status using the loaded readings, so a stale `active` row isn't
  /// shown as "Live" (matches the Monitor Sessions list).
  ActivityStatus get _status =>
      activityStatusOf(_s, lastReadingAt: lastReadingTime(_readings));

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final readings = await _loadReadings(_s.sessionId);
      if (!mounted) return;
      setState(() {
        _readings = readings;
        _data = SessionDetailData.build(session: _s, readings: readings);
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _displayId {
    final t = _s.startTime.toLocal();
    return 'SES-${DateFormat('yyMMdd').format(t)}-${DateFormat('HHmm').format(t)}';
  }

  String get _initials {
    if (widget.initials != null && widget.initials!.isNotEmpty) {
      return widget.initials!;
    }
    final parts = widget.userName.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
    return widget.userName.isNotEmpty ? widget.userName[0].toUpperCase() : '?';
  }

  void _snack(String message, [Color? color]) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  void _copyId() {
    Clipboard.setData(ClipboardData(text: _displayId));
    _snack('Session ID copied', MedsColors.greenDark);
  }

  void _toggleFlag() {
    setState(() => _flagged = !_flagged);
    _snack(_flagged ? 'Marked for review' : 'Review flag removed',
        _flagged ? MedsColors.amber : null);
  }

  void _exportReport() {
    final d = _data ?? SessionDetailData.empty();
    final report = StringBuffer()
      ..writeln('MEDS — Session Report')
      ..writeln('Session: $_displayId')
      ..writeln('User: ${widget.userName}')
      ..writeln('Status: ${_status.label}')
      ..writeln('Start: ${DateFormat('d MMM yyyy, h:mm a').format(_s.startTime.toLocal())}')
      ..writeln('Duration: ${_fmtDuration(d.duration)}')
      ..writeln('Avg BPM: ${d.avgBpm}   Peak BPM: ${d.peakBpm}')
      ..writeln('Dominant emotion: ${d.dominantEmotion}')
      ..writeln('Final state: ${d.finalState}')
      ..writeln('Sensor quality: ${d.sensorQuality}')
      ..writeln('AI summary: ${d.aiSummary ?? '—'}');
    Clipboard.setData(ClipboardData(text: report.toString()));
    _snack('Report copied to clipboard', MedsColors.purple);
  }

  void _viewFullLogs() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (context, controller) {
          final logs = List<EmotionReading>.from(_readings)
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
          return Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Full session logs',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
              Expanded(
                child: logs.isEmpty
                    ? const Center(
                        child: Text('No readings recorded for this session.',
                            style: TextStyle(color: MedsColors.muted)))
                    : ListView.separated(
                        controller: controller,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: logs.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final r = logs[i];
                          final t = r.createdAt
                              .difference(_s.startTime)
                              .inSeconds
                              .clamp(0, 1 << 31);
                          final m = (t ~/ 60).toString().padLeft(2, '0');
                          final sec = (t % 60).toString().padLeft(2, '0');
                          return ListTile(
                            dense: true,
                            leading: Text('$m:$sec',
                                style: const TextStyle(fontSize: 12.5)),
                            title: Text(r.emotion),
                            trailing: Text(
                                '${r.hr > 0 ? '${r.hr} BPM' : '—'} · ${r.sensorQuality}',
                                style: const TextStyle(
                                    color: MedsColors.muted, fontSize: 12)),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openEmotionDetails() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EmotionAnalyticsScreen(
        userId: _s.userId,
        title: widget.userName,
        avatarUrl: widget.avatarUrl,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final color = sessionStatusColor(_status);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(
              child: _error != null && _data == null
                  ? _ErrorView(onRetry: _load)
                  : RefreshIndicator(
                      color: MedsColors.purple,
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                        children: [
                          _infoCard(color),
                          const SizedBox(height: 14),
                          if (_loading && _data == null)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 50),
                              child: Center(
                                  child: CircularProgressIndicator(
                                      color: MedsColors.purple)),
                            )
                          else ...[
                            HrTrendChart(
                                points: _data?.hrTrend ?? const [],
                                avgBpm: _data?.avgBpm ?? 0),
                            const SizedBox(height: 14),
                            _timelineCard(),
                            const SizedBox(height: 14),
                            _overviewCard(),
                            const SizedBox(height: 14),
                            _aiCard(),
                            const SizedBox(height: 14),
                            _flagsCard(),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- Header -------------------------------------------------------------

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 20),
            onPressed: () => Navigator.of(context).maybePop(),
            tooltip: 'Back',
          ),
          const Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Session Details',
                      style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.bold,
                          height: 1.1,
                          color: MedsColors.lightText)),
                  SizedBox(height: 2),
                  Text('Review individual monitoring session',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: MedsColors.muted, fontSize: 12)),
                ],
              ),
            ),
          ),
          AdminHeaderButton(
            icon: _flagged ? Icons.flag : Icons.flag_outlined,
            tooltip: 'Mark for review',
            color: MedsColors.amber,
            onTap: _toggleFlag,
          ),
          const SizedBox(width: 8),
          AdminHeaderButton(
            icon: Icons.file_download_outlined,
            tooltip: 'Export report',
            onTap: _exportReport,
          ),
          const SizedBox(width: 4),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: MedsColors.muted),
            onSelected: (v) {
              switch (v) {
                case 'copy':
                  _copyId();
                case 'logs':
                  _viewFullLogs();
                case 'refresh':
                  _load();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'copy', child: Text('Copy session ID')),
              PopupMenuItem(value: 'logs', child: Text('View full logs')),
              PopupMenuItem(value: 'refresh', child: Text('Refresh')),
            ],
          ),
        ],
      ),
    );
  }

  // ---- User + session info ------------------------------------------------

  Widget _infoCard(Color color) {
    final hasPhoto = widget.avatarUrl != null && widget.avatarUrl!.isNotEmpty;
    final d = _data;
    return AppCard(
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 60,
                height: 60,
                child: Stack(children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: color.withValues(alpha: 0.15),
                    backgroundImage:
                        hasPhoto ? NetworkImage(widget.avatarUrl!) : null,
                    child: hasPhoto
                        ? null
                        : Text(_initials,
                            style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.bold,
                                fontSize: 18)),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 15,
                      height: 15,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Theme.of(context).colorScheme.surface,
                            width: 2),
                      ),
                    ),
                  ),
                ]),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(widget.userName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 8),
                        _statusPill(color),
                      ],
                    ),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: _copyId,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: MedsColors.muted.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(_displayId,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13)),
                            ),
                            const SizedBox(width: 6),
                            const Icon(Icons.copy,
                                size: 14, color: MedsColors.muted),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.calendar_today_outlined,
                            size: 13, color: MedsColors.muted),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            '${DateFormat('d MMM yyyy').format(_s.startTime.toLocal())}  •  ${DateFormat('h:mm a').format(_s.startTime.toLocal())}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: MedsColors.muted, fontSize: 12.5),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 78,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              children: [
                _summaryChip(Icons.sentiment_satisfied_alt, MedsColors.purple,
                    d?.dominantEmotion ?? '—', 'Detected Emotion'),
                const SizedBox(width: 10),
                _summaryChip(Icons.favorite, MedsColors.coral,
                    d == null || d.avgBpm == 0 ? '—' : '${d.avgBpm} BPM',
                    'Avg Heart Rate'),
                const SizedBox(width: 10),
                _summaryChip(Icons.timer_outlined, MedsColors.blue,
                    _fmtDuration(d?.duration ?? Duration.zero), 'Duration'),
                const SizedBox(width: 10),
                _summaryChip(Icons.spa_outlined, MedsColors.greenDark,
                    d?.finalState ?? '—', 'Final State'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPill(Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline, size: 13, color: color),
          const SizedBox(width: 5),
          Text(_status.label,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.bold, fontSize: 11.5)),
        ],
      ),
    );
  }

  Widget _summaryChip(
      IconData icon, Color color, String value, String label) {
    return Container(
      width: 168,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14.5)),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(color: MedsColors.muted, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---- Emotion timeline ---------------------------------------------------

  Widget _timelineCard() {
    final segments = _data?.emotionTimeline ?? const [];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Emotion Timeline',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5)),
              ),
              if (segments.isNotEmpty)
                InkWell(
                  onTap: _openEmotionDetails,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('View details',
                          style: TextStyle(
                              color: MedsColors.purple,
                              fontWeight: FontWeight.w600,
                              fontSize: 13)),
                      Icon(Icons.chevron_right,
                          color: MedsColors.purple, size: 18),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (segments.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No emotion data for this session.',
                  style: TextStyle(color: MedsColors.muted, fontSize: 13)),
            )
          else ...[
            _timelineBar(segments),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final seg in segments)
                  Expanded(child: _segmentLabel(seg)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _timelineBar(List<EmotionSegment> segments) {
    final total = segments.last.endSec - segments.first.startSec;
    return SizedBox(
      height: 16,
      child: Row(
        children: [
          for (var i = 0; i < segments.length; i++)
            Expanded(
              flex: total <= 0
                  ? 1
                  : ((segments[i].endSec - segments[i].startSec) /
                          total *
                          1000)
                      .round()
                      .clamp(1, 1000),
              child: Container(
                margin: EdgeInsets.only(right: i == segments.length - 1 ? 0 : 3),
                decoration: BoxDecoration(
                  color: _emotionTint(segments[i].emotion),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _segmentLabel(EmotionSegment seg) {
    final color = _emotionTint(seg.emotion);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        children: [
          Icon(_emotionIcon(seg.emotion), color: color, size: 18),
          const SizedBox(height: 3),
          Text(seg.emotion,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('${_mmss(seg.startSec)} – ${_mmss(seg.endSec)}',
                style: const TextStyle(color: MedsColors.muted, fontSize: 10.5)),
          ),
        ],
      ),
    );
  }

  // ---- Session overview ---------------------------------------------------

  Widget _overviewCard() {
    final d = _data ?? SessionDetailData.empty();
    final end = _s.endTime;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Session Overview',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5)),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: [
                    _ovRow(Icons.person_outline, MedsColors.purple, 'User',
                        widget.userName),
                    _ovRow(Icons.calendar_today_outlined, MedsColors.blue,
                        'Start Time',
                        DateFormat('d MMM, h:mm a').format(_s.startTime.toLocal())),
                    _ovRow(Icons.flag_outlined, MedsColors.muted, 'End Time',
                        end != null
                            ? DateFormat('d MMM, h:mm a').format(end.toLocal())
                            : '—'),
                    _ovRow(Icons.favorite, MedsColors.coral, 'Avg BPM',
                        d.avgBpm == 0 ? '—' : '${d.avgBpm} BPM'),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  children: [
                    _ovRow(Icons.trending_up, MedsColors.coral, 'Peak BPM',
                        d.peakBpm == 0 ? '—' : '${d.peakBpm} BPM'),
                    _ovRow(Icons.sentiment_satisfied_alt, MedsColors.purple,
                        'Dominant', d.dominantEmotion),
                    _ovPillRow(Icons.verified_user_outlined, MedsColors.greenDark,
                        'Sensor', d.sensorQuality, _qualityColor(d.sensorQuality)),
                    _ovPillRow(Icons.smart_toy_outlined, MedsColors.blue,
                        'AI Status', _aiStatusLabel(d.aiStatus),
                        _aiStatusColor(d.aiStatus)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _ovRow(IconData icon, Color color, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style:
                        const TextStyle(color: MedsColors.muted, fontSize: 11)),
                const SizedBox(height: 1),
                Text(value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 12.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ovPillRow(IconData icon, Color color, String label, String value,
      Color pillColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style:
                        const TextStyle(color: MedsColors.muted, fontSize: 11)),
                const SizedBox(height: 3),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: pillColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(value,
                      style: TextStyle(
                          color: pillColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 11.5)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---- AI summary ---------------------------------------------------------

  Widget _aiCard() {
    final d = _data;
    final text = d?.aiSummary ??
        (d?.aiStatus == 'failed'
            ? 'The AI wellness summary could not be generated for this session.'
            : 'No AI wellness summary has been generated for this session yet.');
    return AppCard(
      color: MedsColors.purple.withValues(alpha: 0.06),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: MedsColors.purple.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.auto_awesome,
                color: MedsColors.purple, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('AI Session Summary',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 6),
                Text(text,
                    style: const TextStyle(
                        fontSize: 13.5, height: 1.5, color: MedsColors.lightText)),
                const SizedBox(height: 8),
                const Text('Wellness insight — not a medical diagnosis.',
                    style: TextStyle(
                        color: MedsColors.muted,
                        fontSize: 11,
                        fontStyle: FontStyle.italic)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---- Flags & review -----------------------------------------------------

  Widget _flagsCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 2, bottom: 10),
          child: Text('Flags & Review',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5)),
        ),
        _actionRow(Icons.flag_outlined, MedsColors.amber,
            _flagged ? 'Marked for Review' : 'Mark for Review', _toggleFlag),
        const SizedBox(height: 10),
        _actionRow(Icons.description_outlined, MedsColors.purple,
            'Export Report', _exportReport),
        const SizedBox(height: 10),
        _actionRow(Icons.article_outlined, MedsColors.blue, 'View Full Logs',
            _viewFullLogs),
      ],
    );
  }

  Widget _actionRow(
      IconData icon, Color color, String label, VoidCallback onTap) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 14)),
          ),
          const Icon(Icons.chevron_right, color: MedsColors.muted),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

String _fmtDuration(Duration d) {
  if (d.inSeconds <= 0) return '—';
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return d.inHours > 0 ? '${d.inHours}h ${m}m' : '${m}m ${s}s';
}

String _mmss(num seconds) {
  final s = seconds.round();
  final m = (s ~/ 60).toString().padLeft(2, '0');
  final sec = (s % 60).toString().padLeft(2, '0');
  return '$m:$sec';
}

Color _emotionTint(String e) => switch (e) {
      'Happy' => MedsColors.purple,
      'Surprise' => MedsColors.teal,
      'Neutral' => MedsColors.amber,
      'Sad' => MedsColors.blue,
      'Fear' => MedsColors.purple,
      'Angry' => MedsColors.coral,
      'Disgust' => MedsColors.amber,
      _ => MedsColors.muted,
    };

IconData _emotionIcon(String e) => switch (e) {
      'Happy' => Icons.sentiment_very_satisfied,
      'Surprise' => Icons.sentiment_satisfied_alt,
      'Neutral' => Icons.sentiment_neutral,
      'Sad' => Icons.sentiment_dissatisfied,
      'Fear' => Icons.sentiment_dissatisfied,
      'Angry' => Icons.sentiment_very_dissatisfied,
      'Disgust' => Icons.sentiment_very_dissatisfied,
      _ => Icons.sentiment_neutral,
    };

Color _qualityColor(String q) => switch (q) {
      'Good' => MedsColors.greenDark,
      'Fair' => MedsColors.amber,
      'Poor' => MedsColors.red,
      _ => MedsColors.muted,
    };

String _aiStatusLabel(String s) => switch (s) {
      'completed' => 'Reviewed',
      'processing' => 'Processing',
      'failed' => 'Failed',
      _ => 'Pending',
    };

Color _aiStatusColor(String s) => switch (s) {
      'completed' => MedsColors.blue,
      'processing' => MedsColors.amber,
      'failed' => MedsColors.red,
      _ => MedsColors.muted,
    };

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: EmptyState(
        icon: Icons.cloud_off_outlined,
        color: MedsColors.red,
        title: 'Could not load session',
        message: 'Something went wrong while loading this session.',
        action: FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Try Again'),
        ),
      ),
    );
  }
}
