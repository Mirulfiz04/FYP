import 'package:flutter/material.dart';

import '../services/notification_prefs.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';

/// Lets the user toggle which notifications they receive. Critical sensor and
/// camera warnings still appear as in-app status during an active session even
/// when their switch (and OS push) is off — noted on this page.
class NotificationSettingsScreen extends StatelessWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notification settings')),
      body: ListenableBuilder(
        listenable: notificationPrefs,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  _switch(
                    title: 'Sensor & Camera alerts',
                    subtitle:
                        'Disconnections, no-finger, camera and signal warnings',
                    value: notificationPrefs.sensorCamera,
                    onChanged: notificationPrefs.setSensorCamera,
                    icon: Icons.sensors,
                    color: MedsColors.teal,
                  ),
                  const Divider(height: 1),
                  _switch(
                    title: 'Session completed',
                    subtitle: 'When a monitoring session finishes',
                    value: notificationPrefs.sessionCompleted,
                    onChanged: notificationPrefs.setSessionCompleted,
                    icon: Icons.check_circle_outline,
                    color: MedsColors.green,
                  ),
                  const Divider(height: 1),
                  _switch(
                    title: 'AI summary ready',
                    subtitle: 'When your AI session insight is generated',
                    value: notificationPrefs.aiSummary,
                    onChanged: notificationPrefs.setAiSummary,
                    icon: Icons.auto_awesome,
                    color: MedsColors.purple,
                  ),
                  const Divider(height: 1),
                  _switch(
                    title: 'Weekly emotional trends',
                    subtitle: 'A weekly summary comparing this week to last',
                    value: notificationPrefs.weeklyTrend,
                    onChanged: notificationPrefs.setWeeklyTrend,
                    icon: Icons.insights_outlined,
                    color: MedsColors.blue,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: MedsColors.amber.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
                border:
                    Border.all(color: MedsColors.amber.withValues(alpha: 0.4)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: MedsColors.amber),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'For your safety, critical sensor and camera warnings still '
                      'appear on-screen during an active session even if these '
                      'switches are off.',
                      style: TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _switch({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required IconData icon,
    required Color color,
  }) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      activeThumbColor: color,
      secondary: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
      subtitle: Text(subtitle,
          style: const TextStyle(fontSize: 12, color: MedsColors.muted)),
    );
  }
}
