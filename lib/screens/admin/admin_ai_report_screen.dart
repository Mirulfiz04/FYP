import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../models/ai_admin_report.dart';
import '../../services/admin_service.dart';
import '../../services/ai_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/insight_bullets.dart';
import '../../widgets/ui_kit.dart';

/// Admin "Detailed AI Report": turns the platform's aggregated statistics into
/// a written, shareable report (executive summary, emotional climate,
/// engagement, key findings, concerns, recommendations). On-brand with the rest
/// of the admin redesign; the AI text is a wellness insight, not a diagnosis.
class AdminAiReportScreen extends StatefulWidget {
  /// Injected in tests; default to the real services.
  final Future<AdminStats> Function()? statsLoader;
  final Future<AiAdminReport> Function(String dataSummary)? generate;

  const AdminAiReportScreen({super.key, this.statsLoader, this.generate});

  @override
  State<AdminAiReportScreen> createState() => _AdminAiReportScreenState();
}

class _AdminAiReportScreenState extends State<AdminAiReportScreen> {
  late final _statsLoader =
      widget.statsLoader ?? () => AdminService().fetchStats();
  late final _generateReport = widget.generate ??
      (String s) => AiService().generateAdminReport(dataSummary: s);

  AdminStats? _stats;
  bool _loading = true;

  AiAdminReport? _report;
  bool _reportLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final stats = await _statsLoader();
      if (mounted) setState(() => _stats = stats);
    } catch (_) {
      // Best effort — the generate button surfaces a clearer error.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmtDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}h ${m}m ${s}s' : '${m}m ${s}s';
  }

  /// Compact, anonymized statistics summary fed to the AI (and reused as the
  /// header when copying the report).
  String _buildSummary(AdminStats s) {
    final now = DateFormat('dd MMM yyyy HH:mm').format(DateTime.now());
    final sample = s.emotionSampleSize;
    final dist = (s.emotionCounts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .map((e) {
      final pct = sample > 0 ? (e.value / sample * 100).round() : 0;
      return '- ${e.key}: ${e.value} ($pct%)';
    }).join('\n');

    final contributors = s.perUser.take(5).map((u) {
      return '- ${u.label}: ${u.readingCount} readings, '
          'dominant ${u.dominantEmotion}'
          '${u.avgHr > 0 ? ', avg HR ${u.avgHr}' : ''}';
    }).join('\n');

    return '''
MEDS PLATFORM REPORT
Generated: $now

USERS
  Total: ${s.totalUsers} (admins: ${s.totalAdmins})

SESSIONS
  Total: ${s.totalSessions} (active: ${s.activeSessions}, completed: ${s.completedSessions})
  Average length: ${_fmtDuration(s.avgSessionDuration)}

READINGS
  Total: ${s.totalReadings} (latest $sample analyzed)
  Emotion distribution (sample):
${dist.isEmpty ? '  - none' : dist}

TOP CONTRIBUTORS (by readings)
${contributors.isEmpty ? '  - none' : contributors}
''';
  }

  Future<void> _generate() async {
    if (_stats == null) {
      await _load();
      if (_stats == null) return;
    }
    setState(() {
      _reportLoading = true;
      _error = null;
    });
    try {
      final report = await _generateReport(_buildSummary(_stats!));
      if (mounted) {
        setState(() {
          _report = report;
          _reportLoading = false;
        });
      }
    } on AiException catch (e) {
      if (mounted) {
        setState(() {
          _reportLoading = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _reportLoading = false;
          _error = 'Something went wrong generating the report.';
        });
      }
    }
  }

  Future<void> _copy() async {
    final s = _stats;
    final r = _report;
    if (s == null || r == null) return;
    final header = '${_buildSummary(s)}\n'
        '============================================================\n'
        'AI ANALYSIS\n';
    await Clipboard.setData(ClipboardData(text: r.toPlainText(header: header)));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Report copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detailed AI Report'),
        actions: [
          if (_report != null)
            IconButton(
              icon: const Icon(Icons.copy_all_outlined),
              tooltip: 'Copy report',
              onPressed: _copy,
            ),
          IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Reload data',
              onPressed: _load),
        ],
      ),
      body: _loading && _stats == null
          ? const Center(
              child: CircularProgressIndicator(color: MedsColors.purple))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _overviewCard(_stats),
                const SizedBox(height: 16),
                _reportCard(),
              ],
            ),
    );
  }

  Widget _overviewCard(AdminStats? s) {
    final items = [
      ('Users', '${s?.totalUsers ?? '—'}'),
      ('Sessions', '${s?.totalSessions ?? '—'}'),
      ('Active', '${s?.activeSessions ?? '—'}'),
      ('Readings', '${s?.totalReadings ?? '—'}'),
    ];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Data in this report',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5)),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final it in items)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(it.$2,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 20)),
                      const SizedBox(height: 2),
                      Text(it.$1,
                          style: const TextStyle(
                              color: MedsColors.muted, fontSize: 11.5)),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _reportCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: MedsColors.purple.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.auto_awesome,
                    size: 16, color: MedsColors.purple),
              ),
              const SizedBox(width: 9),
              const Text('AI Report',
                  style:
                      TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5)),
            ],
          ),
          const SizedBox(height: 14),
          if (_reportLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Column(children: [
                  CircularProgressIndicator(color: MedsColors.purple),
                  SizedBox(height: 12),
                  Text('Writing the report…',
                      style: TextStyle(color: MedsColors.muted, fontSize: 13)),
                ]),
              ),
            )
          else if (_report != null) ...[
            _reportBody(_report!),
            const SizedBox(height: 12),
            const Text('AI wellness insight for administrators — not a medical '
                'diagnosis.',
                style: TextStyle(
                    color: MedsColors.muted,
                    fontSize: 11,
                    fontStyle: FontStyle.italic)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _copy,
                    icon: const Icon(Icons.copy_all_outlined, size: 18),
                    label: const Text('Copy report'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextButton.icon(
                    onPressed: _generate,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Regenerate'),
                    style:
                        TextButton.styleFrom(foregroundColor: MedsColors.purple),
                  ),
                ),
              ],
            ),
          ] else ...[
            const Text(
              'Generate a written, shareable report from the platform data '
              'above: an executive summary, the emotional climate, engagement, '
              'key findings, concerns, and recommendations.',
              style: TextStyle(
                  color: MedsColors.muted, fontSize: 13, height: 1.4),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: MedsColors.red.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline,
                        color: MedsColors.red, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_error!,
                          style: const TextStyle(
                              color: MedsColors.red, fontSize: 12.5)),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.icon(
                onPressed: _generate,
                style:
                    FilledButton.styleFrom(backgroundColor: MedsColors.purple),
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('Generate AI Report'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _reportBody(AiAdminReport r) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _block('Executive summary', r.executiveSummary),
        const SizedBox(height: 14),
        _block('Emotional climate', r.emotionalClimate),
        const SizedBox(height: 14),
        _block('Engagement', r.engagement),
        const SizedBox(height: 16),
        InsightBulletList(
            title: 'Key findings',
            icon: Icons.insights_outlined,
            color: MedsColors.blue,
            items: r.keyFindings),
        if (r.keyFindings.isNotEmpty) const SizedBox(height: 14),
        InsightBulletList(
            title: 'Concerns',
            icon: Icons.warning_amber_rounded,
            color: MedsColors.amber,
            items: r.concerns),
        if (r.concerns.isNotEmpty) const SizedBox(height: 14),
        InsightBulletList(
            title: 'Recommendations',
            icon: Icons.lightbulb_outline,
            color: MedsColors.greenDark,
            items: r.recommendations),
      ],
    );
  }

  Widget _block(String title, String body) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
        const SizedBox(height: 4),
        Text(body, style: const TextStyle(fontSize: 13, height: 1.45)),
      ],
    );
  }
}
