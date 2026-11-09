import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'session_history_card.dart' show historyStateColor;
import 'ui_kit.dart';

/// The three stacked cards beside the camera: Detected Emotion, Confidence and
/// Current State. Values are bound to the live controller — never hard-coded.
class EmotionResultCards extends StatelessWidget {
  final String emotion;
  final double confidence;
  final String state;

  const EmotionResultCards({
    super.key,
    required this.emotion,
    required this.confidence,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final emoColor = MedsColors.emotion(emotion);
    final stateColor = historyStateColor(state);
    return Column(
      children: [
        _card(
          label: 'Detected Emotion',
          value: emotion == 'Detecting...' ? 'Detecting…' : emotion,
          color: emoColor,
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                color: emoColor.withValues(alpha: 0.18), shape: BoxShape.circle),
            child: Center(
                child: Text(MedsColors.emoji(emotion),
                    style: const TextStyle(fontSize: 20))),
          ),
        ),
        const SizedBox(height: 10),
        _card(
          label: 'Confidence',
          value: '${confidence.round()}%',
          color: MedsColors.purple,
          leading: _iconCircle(Icons.verified_user, MedsColors.purple),
        ),
        const SizedBox(height: 10),
        _card(
          label: 'Current State',
          value: state,
          color: stateColor,
          leading: _iconCircle(Icons.eco, stateColor),
        ),
      ],
    );
  }

  Widget _iconCircle(IconData icon, Color color) => Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 20),
      );

  Widget _card({
    required String label,
    required String value,
    required Color color,
    required Widget leading,
  }) {
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: MedsColors.muted, fontSize: 11.5)),
                const SizedBox(height: 2),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: color == MedsColors.purple
                            ? MedsColors.purple
                            : null)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
