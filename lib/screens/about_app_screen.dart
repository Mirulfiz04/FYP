import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';

const Color _accent = Color(0xFF6A5AE0);

const String _disclaimer =
    'This application is designed for emotional wellness monitoring and '
    'educational purposes. It does not provide medical diagnosis or replace '
    'professional medical advice.';

class AboutAppScreen extends StatelessWidget {
  const AboutAppScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About App')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.psychology, size: 38, color: _accent),
                ),
                const SizedBox(height: 12),
                const Text('MEDS',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('Version 1.0.0 (build 1)',
                    style: TextStyle(color: MedsColors.muted, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('About',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                SizedBox(height: 6),
                Text(
                  'MEDS combines on-device facial-emotion detection with an '
                  'ESP32 heart-rate sensor to help you understand and monitor '
                  'your emotional wellbeing, with AI-assisted wellness insights.',
                  style: TextStyle(fontSize: 13, height: 1.45),
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.medical_information_outlined, color: MedsColors.amber),
                SizedBox(width: 12),
                Expanded(
                  child: Text(_disclaimer,
                      style: TextStyle(fontSize: 12.5, height: 1.45)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: const [
                _LegalTile(
                  title: 'Terms of Service',
                  body:
                      'By using MEDS you agree to use it for personal wellbeing '
                      'and educational purposes only, and not as a medical '
                      'device. The app is provided as-is for a student project.',
                ),
                Divider(height: 1),
                _LegalTile(
                  title: 'Privacy Policy',
                  body:
                      'MEDS stores your emotion and heart-rate data to your '
                      'account to show your history and insights. You can delete '
                      'your data at any time from Privacy & Security.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('Developer',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                SizedBox(height: 6),
                Text(
                  'Final-year Software Engineering project.\n'
                  'Universiti Teknikal Malaysia Melaka (UTeM).',
                  style: TextStyle(fontSize: 13, height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LegalTile extends StatelessWidget {
  final String title;
  final String body;
  const _LegalTile({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text(title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(body, style: const TextStyle(fontSize: 13, height: 1.45)),
        ),
      ],
    );
  }
}
