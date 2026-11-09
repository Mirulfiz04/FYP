import 'package:flutter/material.dart';

import '../models/ai_insight.dart';
import '../models/detection_session.dart';
import '../services/ai_summary_service.dart';
import '../theme/app_theme.dart';
import 'ui_kit.dart';

/// Shows the AI wellness insight stored against a session, tracking its status
/// (pending | processing | completed | failed) with a Retry action on failure.
/// Always framed as a wellness insight — never a medical diagnosis.
class SessionAiSummaryCard extends StatefulWidget {
  final DetectionSession session;
  const SessionAiSummaryCard({super.key, required this.session});

  @override
  State<SessionAiSummaryCard> createState() => _SessionAiSummaryCardState();
}

class _SessionAiSummaryCardState extends State<SessionAiSummaryCard> {
  static const _green = Color(0xFF00DC64);

  late String _status = widget.session.aiSummaryStatus;
  late AiInsight? _insight = widget.session.aiSummary;
  late String? _error = widget.session.aiSummaryError;
  bool _busy = false;

  Future<void> _generate() async {
    setState(() {
      _busy = true;
      _status = 'processing';
      _error = null;
    });
    final insight = await AiSummaryService().generateForSession(
      widget.session.sessionId,
      userId: widget.session.userId,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (insight != null) {
        _insight = insight;
        _status = 'completed';
      } else {
        _status = 'failed';
        _error ??= 'AI insight could not be generated. Please try again.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.auto_awesome, size: 16, color: _green),
              SizedBox(width: 6),
              Text('AI SESSION INSIGHT',
                  style: TextStyle(
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 1)),
            ],
          ),
          const SizedBox(height: 12),
          _content(),
          const SizedBox(height: 10),
          const Text(
            'This is a wellness insight to support self-awareness — not a medical '
            'diagnosis.',
            style: TextStyle(color: Colors.grey, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _content() {
    if (_busy || _status == 'processing') {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: _green)),
            SizedBox(width: 12),
            Expanded(child: Text('Generating your AI insight…')),
          ],
        ),
      );
    }

    if (_status == 'completed' && _insight != null) {
      return _InsightView(insight: _insight!);
    }

    if (_status == 'failed') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _error?.isNotEmpty == true
                ? 'AI insight could not be generated. Please try again.'
                : 'AI insight could not be generated. Please try again.',
            style: const TextStyle(color: MedsColors.red, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _generate,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
            ),
          ),
        ],
      );
    }

    // pending / no summary yet
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Get an AI summary of how you felt during this session, with trends '
          'and a few personalized wellness tips.',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _generate,
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: const Text('Generate AI insight'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _green,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }
}

/// Read-only rendering of a completed [AiInsight].
class _InsightView extends StatelessWidget {
  final AiInsight insight;
  const _InsightView({required this.insight});

  @override
  Widget build(BuildContext context) {
    final color = MedsColors.stress(insight.stressLevel);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.monitor_heart, size: 14, color: color),
              const SizedBox(width: 6),
              Text('Stress level: ${insight.stressLevel}',
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _block('Summary', insight.emotionalSummary),
        const SizedBox(height: 14),
        _block('Trend analysis', insight.trendAnalysis),
        const SizedBox(height: 14),
        const Text('Recommendations',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 6),
        ...insight.recommendations.map((r) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.check_circle,
                        size: 14, color: Color(0xFF00DC64)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(r,
                          style:
                              const TextStyle(fontSize: 13, height: 1.35))),
                ],
              ),
            )),
      ],
    );
  }

  Widget _block(String title, String body) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 4),
        Text(body.isEmpty ? '—' : body,
            style: const TextStyle(fontSize: 13, height: 1.4)),
      ],
    );
  }
}
