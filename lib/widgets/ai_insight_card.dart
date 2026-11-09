import 'package:flutter/material.dart';

import '../models/ai_insight.dart';
import '../models/emotion_reading.dart';
import '../services/ai_service.dart';
import '../services/insight_cache.dart';
import '../theme/app_theme.dart';
import 'ui_kit.dart';

/// A self-contained card that generates and shows an AI wellness insight
/// (summary, stress level, trend analysis, recommendations).
///
/// Provide [fetchReadings] — called when the user taps the generate button — so
/// the same card works whether the readings are already in memory (analytics /
/// session detail) or need loading on demand (home dashboard).
class AiInsightCard extends StatefulWidget {
  final Future<List<EmotionReading>> Function() fetchReadings;
  final String title;
  final String emptyHint;
  final String buttonLabel;

  /// When true, the insight is generated automatically as soon as the card is
  /// shown (used on the home dashboard). When false, the user taps the button.
  final bool autoGenerate;

  /// When set, the generated insight is cached under this key and only
  /// regenerated when the reading data changes. The cached summary is shown
  /// instantly on the next load (and works offline). Make it unique per user.
  final String? cacheKey;

  const AiInsightCard({
    super.key,
    required this.fetchReadings,
    this.title = 'AI WELLNESS INSIGHTS',
    this.emptyHint =
        'Let AI summarize how you have been feeling, spot trends in your '
        'emotions and heart rate, and suggest personalized wellness tips.',
    this.buttonLabel = 'Generate AI Insights',
    this.autoGenerate = false,
    this.cacheKey,
  });

  @override
  State<AiInsightCard> createState() => _AiInsightCardState();
}

class _AiInsightCardState extends State<AiInsightCard> {
  static const _green = Color(0xFF00DC64);

  final _ai = AiService();
  AiInsight? _insight;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.autoGenerate) {
      // Defer until after the first frame so setState is safe.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _autoLoad();
      });
    }
  }

  /// A short fingerprint of the data: total count + newest reading time.
  /// Changes whenever new readings are recorded.
  String _markerFor(List<EmotionReading> readings) {
    if (readings.isEmpty) return 'empty';
    return '${readings.length}_${readings.first.createdAt.toIso8601String()}';
  }

  /// Auto path (home): show any cached summary instantly, then regenerate only
  /// if the reading data has changed since that summary was made.
  Future<void> _autoLoad() async {
    CachedInsight? cached;
    if (widget.cacheKey != null) {
      cached = await InsightCache.load(widget.cacheKey!);
      if (cached != null && mounted) {
        setState(() => _insight = cached!.insight); // show instantly
      }
    }

    // Only show a spinner if there's nothing cached to display yet.
    if (_insight == null && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    List<EmotionReading> readings;
    try {
      readings = await widget.fetchReadings();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
      return; // keep showing the cached summary (if any), or the hint
    }

    // Data unchanged since the cached summary — nothing to regenerate.
    if (cached != null && cached.marker == _markerFor(readings)) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    if (readings.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return; // no data yet — show cached (if any) or the hint
    }

    // New data (or no cache) — regenerate, keeping the old summary visible
    // while the request runs.
    await _runGeneration(readings);
  }

  /// Manual path (button / Regenerate): always fetch fresh and regenerate.
  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final readings = await widget.fetchReadings().catchError(
          (_) => <EmotionReading>[],
        );
    if (readings.isEmpty) {
      // No data yet — fall back to the hint + button instead of an error.
      if (mounted) setState(() => _loading = false);
      return;
    }
    await _runGeneration(readings);
  }

  /// Calls the AI service for [readings], caches the result if [cacheKey] is
  /// set, and updates the UI.
  Future<void> _runGeneration(List<EmotionReading> readings) async {
    if (_insight == null && mounted) setState(() => _loading = true);
    try {
      final insight = await _ai.generateInsight(readings);
      if (widget.cacheKey != null) {
        await InsightCache.save(
          widget.cacheKey!,
          insight: insight,
          marker: _markerFor(readings),
        );
      }
      if (mounted) {
        setState(() {
          _insight = insight;
          _loading = false;
        });
      }
    } on AiException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          if (_insight == null) _error = e.message; // don't hide a good summary
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          if (_insight == null) {
            _error = 'Something went wrong generating insights.';
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 16, color: _green),
              const SizedBox(width: 6),
              Text(widget.title,
                  style: const TextStyle(
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 1)),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(color: _green),
                    SizedBox(height: 12),
                    Text('Analyzing your emotional patterns…',
                        style: TextStyle(color: Colors.grey, fontSize: 13)),
                  ],
                ),
              ),
            )
          else if (_insight != null) ...[
            _body(_insight!),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _generate,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Regenerate'),
                style: TextButton.styleFrom(foregroundColor: _green),
              ),
            ),
          ] else ...[
            Text(
              widget.emptyHint,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style:
                      const TextStyle(color: Color(0xFFFF4040), fontSize: 12)),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _generate,
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: Text(widget.buttonLabel),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _body(AiInsight i) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stressBadge(i.stressLevel),
        const SizedBox(height: 14),
        _block('Summary', i.emotionalSummary),
        const SizedBox(height: 14),
        _block('Trend analysis', i.trendAnalysis),
        const SizedBox(height: 14),
        const Text('Recommendations',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 6),
        ...i.recommendations.map((r) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child:
                        Icon(Icons.check_circle, size: 14, color: _green),
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
        Text(body, style: const TextStyle(fontSize: 13, height: 1.4)),
      ],
    );
  }

  Widget _stressBadge(String level) {
    final color = MedsColors.stress(level);
    return Container(
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
          Text('Stress level: $level',
              style: TextStyle(
                  color: color, fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }
}
