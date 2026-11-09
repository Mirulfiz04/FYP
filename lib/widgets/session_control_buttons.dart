import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

const Color _accent = Color(0xFF6A5AE0);

/// Pause/Resume (outlined purple) + Stop (red) controls for the live session.
class SessionControlButtons extends StatelessWidget {
  final bool paused;
  final bool busy;
  final VoidCallback onPauseResume;
  final VoidCallback onStop;

  const SessionControlButtons({
    super.key,
    required this.paused,
    required this.onPauseResume,
    required this.onStop,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: busy ? null : onPauseResume,
            style: OutlinedButton.styleFrom(
              foregroundColor: _accent,
              side: BorderSide(color: _accent.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
            icon: Icon(paused ? Icons.play_arrow : Icons.pause, size: 20),
            label: Text(paused ? 'Resume Session' : 'Pause Session'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            onPressed: busy ? null : onStop,
            style: FilledButton.styleFrom(
              backgroundColor: MedsColors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
            icon: busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.stop, size: 20),
            label: const Text('Stop Session'),
          ),
        ),
      ],
    );
  }
}
