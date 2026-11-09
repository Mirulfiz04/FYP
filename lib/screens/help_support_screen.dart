import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';

const Color _accent = Color(0xFF6A5AE0);
const String _supportEmail = 'support@meds-app.example';

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help & Support')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SectionHeader(
              title: 'Frequently asked questions',
              icon: Icons.help_outline,
              color: _accent),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: const [
                _Faq(
                  q: 'How do I use the heart-rate sensor?',
                  a: 'Power on the ESP32, join the MEDS_ESP32 Wi-Fi on your '
                      'phone (keep mobile data on for internet), then rest a '
                      'fingertip gently on the MAX30102 sensor and keep still.',
                ),
                _Faq(
                  q: 'How should I position my face during detection?',
                  a: 'Face the front camera in good, even lighting. Keep your '
                      'whole face inside the frame and avoid strong backlight '
                      'or shadows.',
                ),
                _Faq(
                  q: 'The camera isn\'t working — what can I do?',
                  a: 'Allow camera permission for MEDS in your device settings, '
                      'close other apps using the camera, then restart the '
                      'session.',
                ),
                _Faq(
                  q: 'The sensor won\'t connect — what can I do?',
                  a: 'Confirm you are on the MEDS_ESP32 Wi-Fi and the sensor '
                      'address in Connected Devices is correct, then tap Retry.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const SectionHeader(
              title: 'Contact', icon: Icons.support_agent, color: MedsColors.teal),
          AppCard(
            child: Column(
              children: [
                _ContactRow(
                  icon: Icons.mail_outline,
                  title: 'Contact support',
                  subtitle: _supportEmail,
                  onCopy: () => _copy(context, 'Support email copied'),
                ),
                const Divider(height: 18),
                _ContactRow(
                  icon: Icons.bug_report_outlined,
                  title: 'Report a problem',
                  subtitle: 'Email us what went wrong',
                  onCopy: () => _copy(context, 'Support email copied'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _copy(BuildContext context, String msg) {
    Clipboard.setData(const ClipboardData(text: _supportEmail));
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _Faq extends StatelessWidget {
  final String q;
  final String a;
  const _Faq({required this.q, required this.a});

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text(q, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(a, style: const TextStyle(fontSize: 13, height: 1.45)),
        ),
      ],
    );
  }
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onCopy;

  const _ContactRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: _accent),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: const TextStyle(color: MedsColors.muted, fontSize: 12.5)),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.copy, size: 18, color: _accent),
          tooltip: 'Copy support email',
          onPressed: onCopy,
        ),
      ],
    );
  }
}
