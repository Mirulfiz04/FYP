import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/detection_session.dart';
import '../theme/app_theme.dart';
import 'ui_kit.dart';

const Color _accent = Color(0xFF6A5AE0);

({Color color, IconData icon, String label}) _statusInfo(String status) =>
    switch (status) {
      'completed' => (
          color: _accent,
          icon: Icons.check_circle,
          label: 'Completed'
        ),
      'active' => (color: MedsColors.greenDark, icon: Icons.sensors, label: 'Active'),
      'cancelled' => (
          color: MedsColors.amber,
          icon: Icons.cancel,
          label: 'Cancelled'
        ),
      _ => (color: MedsColors.red, icon: Icons.error, label: 'Failed'),
    };

/// The top status + session-info card.
class SessionSummaryCard extends StatelessWidget {
  final DetectionSession session;
  final String? userName;
  final bool showUser;

  const SessionSummaryCard({
    super.key,
    required this.session,
    this.userName,
    this.showUser = false,
  });

  @override
  Widget build(BuildContext context) {
    final st = _statusInfo(session.status);
    final start = session.startTime.toLocal();
    final end = session.endTime?.toLocal();
    final dur = end != null ? end.difference(start) : Duration.zero;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                    color: st.color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14)),
                child: Icon(st.icon, color: st.color, size: 26),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('STATUS',
                      style: TextStyle(
                          color: MedsColors.muted,
                          fontSize: 11,
                          letterSpacing: 1)),
                  Text(st.label,
                      style: TextStyle(
                          color: st.color,
                          fontWeight: FontWeight.bold,
                          fontSize: 18)),
                ],
              ),
            ],
          ),
          const Divider(height: 24),
          Row(
            children: [
              _cell(Icons.calendar_month, DateFormat('dd MMM yyyy').format(start),
                  'Date'),
              _div(context),
              _cell(Icons.play_circle_outline,
                  DateFormat('h:mm:ss a').format(start), 'Started'),
              _div(context),
              _cell(
                  Icons.stop_circle_outlined,
                  end != null ? DateFormat('h:mm:ss a').format(end) : '—',
                  'Ended'),
              _div(context),
              _cell(Icons.timer_outlined,
                  '${dur.inMinutes}m ${dur.inSeconds.remainder(60)}s',
                  'Duration'),
            ],
          ),
          const Divider(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _kv(Icons.assignment_outlined, 'SESSION ID',
                    session.sessionId),
              ),
              if (showUser)
                Expanded(
                  child: _kv(Icons.person_outline, 'USER',
                      userName ?? 'Unknown'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _div(BuildContext context) => Container(
      width: 1,
      height: 38,
      color: Theme.of(context).dividerColor,
      margin: const EdgeInsets.symmetric(horizontal: 4));

  Widget _cell(IconData icon, String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: _accent, size: 18),
          const SizedBox(height: 4),
          Text(value,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          Text(label,
              style: const TextStyle(color: MedsColors.muted, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _kv(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: _accent, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      color: MedsColors.muted, fontSize: 10, letterSpacing: 1)),
              const SizedBox(height: 2),
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }
}
