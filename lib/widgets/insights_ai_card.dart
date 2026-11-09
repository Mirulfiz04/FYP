import 'package:flutter/material.dart';

import '../models/ai_insight.dart';
import '../models/emotion_reading.dart';
import '../services/ai_service.dart';
import '../theme/app_theme.dart';
import 'ui_kit.dart';

const Color _accent = Color(0xFF6A5AE0);

typedef InsightGenerator = Future<AiInsight> Function(List<EmotionReading>);

enum _State { loading, done, error }

/// AI wellness-insight card. Gated by [enough]; generates via [generate]
/// (defaults to [AiService.generateInsight], injectable for tests). Shows a
/// loading state, a retry on failure, and a "View Full Insight" sheet for the
/// detailed report. Framed as a wellness insight, never a diagnosis.
class InsightsAiCard extends StatefulWidget {
  final bool enough;
  final Future<List<EmotionReading>> Function() fetchReadings;
  final InsightGenerator? generate;

  /// Changes whenever the period changes, triggering regeneration.
  final Object? regenerateKey;

  const InsightsAiCard({
    super.key,
    required this.enough,
    required this.fetchReadings,
    this.generate,
    this.regenerateKey,
  });

  @override
  State<InsightsAiCard> createState() => _InsightsAiCardState();
}

class _InsightsAiCardState extends State<InsightsAiCard> {
  _State _state = _State.loading;
  AiInsight? _insight;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.enough) _generate();
  }

  @override
  void didUpdateWidget(covariant InsightsAiCard old) {
    super.didUpdateWidget(old);
    if (widget.enough && widget.regenerateKey != old.regenerateKey) {
      _generate();
    }
  }

  Future<void> _generate() async {
    setState(() {
      _state = _State.loading;
      _error = null;
    });
    try {
      final readings = await widget.fetchReadings();
      if (readings.isEmpty) {
        throw const AiException('Not enough valid detections to analyze.');
      }
      final gen = widget.generate ?? AiService().generateInsight;
      final insight = await gen(readings);
      if (!mounted) return;
      setState(() {
        _insight = insight;
        _state = _State.done;
      });
    } on AiException catch (e) {
      if (mounted) setState(() {
        _error = e.message;
        _state = _State.error;
      });
    } catch (_) {
      if (mounted) setState(() {
        _error = 'Something went wrong generating your insight.';
        _state = _State.error;
      });
    }
  }

  void _viewFull() {
    final i = _insight;
    if (i == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FullInsightSheet(insight: i),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.auto_awesome, size: 17, color: _accent),
              SizedBox(width: 6),
              Text('AI Insight',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 12),
          _content(),
        ],
      ),
    );
  }

  Widget _content() {
    if (!widget.enough) {
      return const Text(
        'More completed sessions are required to generate a reliable insight.',
        style: TextStyle(color: MedsColors.muted, fontSize: 13, height: 1.4),
      );
    }
    switch (_state) {
      case _State.loading:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Row(children: [
            SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: _accent)),
            SizedBox(width: 12),
            Expanded(child: Text('Generating your wellness insight…')),
          ]),
        );
      case _State.error:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_error ?? 'Could not generate an insight.',
                style: const TextStyle(color: MedsColors.red, fontSize: 13)),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _generate,
                style: FilledButton.styleFrom(backgroundColor: _accent),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
              ),
            ),
          ],
        );
      case _State.done:
        final i = _insight!;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(i.emotionalSummary,
                      style: const TextStyle(fontSize: 13, height: 1.45)),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: _viewFull,
                    style: TextButton.styleFrom(
                        foregroundColor: _accent, padding: EdgeInsets.zero),
                    icon: const Icon(Icons.open_in_full, size: 15),
                    label: const Text('View Full Insight'),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.psychology_alt, size: 40, color: _accent),
          ],
        );
    }
  }
}

class _FullInsightSheet extends StatelessWidget {
  final AiInsight insight;
  const _FullInsightSheet({required this.insight});

  @override
  Widget build(BuildContext context) {
    final color = MedsColors.stress(insight.stressLevel);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('AI wellness insight',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20)),
                child: Text('Stress level: ${insight.stressLevel}',
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 12)),
              ),
              const SizedBox(height: 14),
              _block('Summary', insight.emotionalSummary),
              const SizedBox(height: 12),
              _block('Trend analysis', insight.trendAnalysis),
              const SizedBox(height: 12),
              const Text('Recommendations',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 4),
              ...insight.recommendations.map((r) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(Icons.check_circle,
                              size: 14, color: Color(0xFF00A84B))),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(r,
                              style:
                                  const TextStyle(fontSize: 13, height: 1.4))),
                    ]),
                  )),
              const SizedBox(height: 12),
              const Text(
                'This is a wellness insight to support self-awareness — not a '
                'medical diagnosis.',
                style: TextStyle(color: MedsColors.muted, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _block(String title, String body) => Column(
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
