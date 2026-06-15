import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'device_check_screen.dart';
import 'emotion_analytics_screen.dart';

class HomeScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  final ValueChanged<int> onOpenTab;
  final VoidCallback onSessionEnded;

  const HomeScreen({
    super.key,
    required this.cameras,
    required this.onOpenTab,
    required this.onSessionEnded,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _auth = AuthService();
  String? _name;

  @override
  void initState() {
    super.initState();
    _loadName();
  }

  Future<void> _loadName() async {
    try {
      final profile = await _auth.loadProfile();
      if (mounted) {
        setState(() => _name = profile.name?.isNotEmpty == true
            ? profile.name
            : profile.email);
      }
    } catch (_) {
      // Greeting is non-critical.
    }
  }

  Future<void> _startSession() async {
    final ranSession = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => DeviceCheckScreen(cameras: widget.cameras),
      ),
    );
    // The live screen pops `true` when a session was actually run.
    if (ranSession == true) widget.onSessionEnded();
  }

  void _openMyAnalytics() {
    final userId = _auth.currentUser?.id;
    if (userId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EmotionAnalyticsScreen(
          userId: userId,
          title: _name ?? 'My analytics',
          subtitle: 'Your emotion & heart-rate analytics',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MEDS')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              _name != null ? 'Hello, $_name 👋' : 'Welcome 👋',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Multimodal Emotional Detection System',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            _DisclaimerCard(),
            const SizedBox(height: 20),
            // Primary action.
            _PrimaryActionCard(onTap: _startSession),
            const SizedBox(height: 20),
            const Text(
              'FEATURES',
              style: TextStyle(
                color: Colors.grey,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 10),
            _FeatureTile(
              icon: Icons.event_note_outlined,
              color: const Color(0xFF00B4FF),
              title: 'My sessions',
              subtitle: 'See when you ran sessions and their details',
              onTap: () => widget.onOpenTab(1),
            ),
            _FeatureTile(
              icon: Icons.insights_outlined,
              color: const Color(0xFF9B30FF),
              title: 'My emotion analytics',
              subtitle: 'Your emotions and heart-rate trends',
              onTap: _openMyAnalytics,
            ),
            _FeatureTile(
              icon: Icons.person_outline,
              color: const Color(0xFFFFA500),
              title: 'Profile & settings',
              subtitle: 'Edit your details, photo and theme',
              onTap: () => widget.onOpenTab(2),
            ),
          ],
        ),
      ),
    );
  }
}

class _DisclaimerCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFA500).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFA500).withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Color(0xFFFFA500)),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'MEDS is for educational and wellbeing awareness only. It does '
              'not provide medical advice or diagnosis. If you feel unwell, '
              'please consult a qualified professional.',
              style: TextStyle(fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryActionCard extends StatelessWidget {
  final VoidCallback onTap;
  const _PrimaryActionCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: medsGreen,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              const Icon(Icons.play_circle_fill, color: Colors.black, size: 40),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Start detection session',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      "We'll check your device first",
                      style: TextStyle(color: Colors.black87, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.black),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _FeatureTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(icon, color: color),
        ),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle,
            style: const TextStyle(color: Colors.grey, fontSize: 12)),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      ),
    );
  }
}
