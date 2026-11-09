import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/session_summary.dart';
import '../theme/app_theme.dart';
import 'ui_kit.dart';

/// Colour for a final-state chip (Calm/Stressed/Excited/Low Mood/Neutral).
Color historyStateColor(String state) => switch (state) {
      'Calm' => MedsColors.greenDark,
      'Content' => MedsColors.teal,
      'Stressed' => MedsColors.amber,
      'Excited' => MedsColors.purple,
      'Low Mood' => MedsColors.blue,
      _ => MedsColors.muted,
    };

/// One session record on the History list.
class SessionHistoryCard extends StatelessWidget {
  final SessionSummary session;
  final VoidCallback onViewSummary;

  /// Multi-select support (History bulk export). When [selectionMode] is on,
  /// tapping the card toggles [selected] instead of opening the summary.
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onSelectToggle;
  final VoidCallback? onLongPress;

  const SessionHistoryCard({
    super.key,
    required this.session,
    required this.onViewSummary,
    this.selectionMode = false,
    this.selected = false,
    this.onSelectToggle,
    this.onLongPress,
  });

  String _durationText(Duration d) =>
      '${d.inMinutes.remainder(60)}m ${d.inSeconds.remainder(60)}s';

  String _headerText(DateTime local) {
    final today = DateTime.now();
    final d = DateTime(local.year, local.month, local.day);
    final t0 = DateTime(today.year, today.month, today.day);
    final diff = t0.difference(d).inDays;
    final time = DateFormat('h:mm a').format(local);
    if (diff == 0) return 'Today, $time';
    if (diff == 1) return 'Yesterday, $time';
    return '${DateFormat('dd MMM yyyy').format(local)}, $time';
  }

  @override
  Widget build(BuildContext context) {
    final s = session;
    final local = s.startTime.toLocal();
    final emotionColor = MedsColors.emotion(s.dominantEmotion);
    final stateColor = historyStateColor(s.finalState);
    final ai = s.aiSummaryStatus;
    final aiColor = ai.isAvailable
        ? MedsColors.purple
        : (ai == AiSummaryStatus.processing ? MedsColors.amber : MedsColors.muted);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onLongPress: onLongPress,
        child: AppCard(
        onTap: selectionMode ? onSelectToggle : onViewSummary,
        color: selected
            ? MedsColors.purple.withValues(alpha: 0.10)
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (selectionMode) ...[
                  Icon(
                    selected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: selected ? MedsColors.purple : MedsColors.muted,
                  ),
                  const SizedBox(width: 10),
                ],
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: MedsColors.purple.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child:
                      const Icon(Icons.calendar_month, color: MedsColors.purple),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_headerText(local),
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14)),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(DateFormat('dd MMM yyyy').format(local),
                              style: const TextStyle(
                                  color: MedsColors.muted, fontSize: 11.5)),
                          const SizedBox(width: 10),
                          const Icon(Icons.schedule,
                              size: 12, color: MedsColors.muted),
                          const SizedBox(width: 3),
                          Text(_durationText(s.duration),
                              style: const TextStyle(
                                  color: MedsColors.muted, fontSize: 11.5)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            Row(
              children: [
                Expanded(
                  child: _metric(
                    'Emotion',
                    Row(
                      children: [
                        Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: emotionColor.withValues(alpha: 0.18),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(MedsColors.emoji(s.dominantEmotion),
                                style: const TextStyle(fontSize: 14)),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(s.dominantEmotion,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: _metric(
                    'Avg. HR',
                    Row(
                      children: [
                        const Icon(Icons.favorite,
                            color: MedsColors.pink, size: 14),
                        const SizedBox(width: 4),
                        Text(s.averageBpm > 0 ? '${s.averageBpm} BPM' : '—',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13)),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: _metric(
                    'State',
                    Pill(text: s.finalState, color: stateColor),
                    alignEnd: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  ai.isAvailable
                      ? Icons.auto_awesome
                      : (ai == AiSummaryStatus.processing
                          ? Icons.hourglass_top
                          : Icons.info_outline),
                  size: 15,
                  color: aiColor,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(ai.label,
                      style: TextStyle(
                          fontSize: 12,
                          color: aiColor,
                          fontWeight: FontWeight.w500)),
                ),
                OutlinedButton(
                  onPressed: selectionMode ? onSelectToggle : onViewSummary,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: MedsColors.purple,
                    side: BorderSide(
                        color: MedsColors.purple.withValues(alpha: 0.4)),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('View Summary', style: TextStyle(fontSize: 12)),
                      Icon(Icons.chevron_right, size: 16),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _metric(String label, Widget value, {bool alignEnd = false}) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: MedsColors.muted, fontSize: 10.5)),
        const SizedBox(height: 5),
        value,
      ],
    );
  }
}
