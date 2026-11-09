import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../services/emotion_classifier.dart';
import '../services/sensor_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_fun.dart';
import '../widgets/ui_kit.dart';
import 'dashboard_screen.dart';

enum _CheckStatus { checking, ok, warn, fail }

class _CheckItem {
  _CheckStatus status;
  String detail;
  _CheckItem(this.status, this.detail);
}

/// Pre-flight screen: verifies camera / model / sensor and collects per-session
/// consent before a detection session is created and started.
class DeviceCheckScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const DeviceCheckScreen({super.key, required this.cameras});

  @override
  State<DeviceCheckScreen> createState() => _DeviceCheckScreenState();
}

class _DeviceCheckScreenState extends State<DeviceCheckScreen> {
  final _supabase = SupabaseService();

  late final _CheckItem _camera = _CheckItem(_CheckStatus.checking, 'Checking…');
  late final _CheckItem _model = _CheckItem(_CheckStatus.checking, 'Checking…');
  late final _CheckItem _cloud = _CheckItem(_CheckStatus.checking, 'Checking…');
  late final _CheckItem _sensor = _CheckItem(_CheckStatus.checking, 'Checking…');

  bool _consent = false;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _runChecks();
  }

  Future<void> _runChecks() async {
    await _checkCamera();
    await _checkModel();
    await _checkCloud();
    await _checkSensor();
  }

  Future<void> _checkCloud() async {
    try {
      await _supabase.ping().timeout(const Duration(seconds: 8));
      setState(() {
        _cloud.status = _CheckStatus.ok;
        _cloud.detail = 'Connected to MEDS cloud';
      });
    } catch (_) {
      setState(() {
        _cloud.status = _CheckStatus.fail;
        _cloud.detail =
            'No internet. Join a Wi-Fi with internet access (not MEDS_ESP32).';
      });
    }
  }

  Future<void> _checkCamera() async {
    final hasCamera = widget.cameras.isNotEmpty;
    final hasFront = widget.cameras
        .any((c) => c.lensDirection == CameraLensDirection.front);
    setState(() {
      _camera.status = hasCamera ? _CheckStatus.ok : _CheckStatus.fail;
      _camera.detail = !hasCamera
          ? 'No camera found on this device'
          : hasFront
              ? 'Front camera ready'
              : 'Using available camera';
    });
  }

  Future<void> _checkModel() async {
    final classifier = EmotionClassifier();
    try {
      await classifier.load();
      setState(() {
        _model.status = _CheckStatus.ok;
        _model.detail = 'Emotion model loaded';
      });
    } catch (e) {
      setState(() {
        _model.status = _CheckStatus.fail;
        _model.detail = 'Failed to load model';
      });
    } finally {
      classifier.close();
    }
  }

  Future<void> _checkSensor() async {
    try {
      final reading = await createSensorService().fetchReading();
      setState(() {
        _sensor.status = _CheckStatus.ok;
        _sensor.detail = 'ESP32 connected (HR ${reading.hr} bpm)';
      });
    } catch (_) {
      setState(() {
        _sensor.status = _CheckStatus.warn;
        _sensor.detail = 'Not connected — emotion still works (camera only)';
      });
    }
  }

  // Required checks must pass; the sensor is optional.
  bool get _requiredPassed =>
      _camera.status == _CheckStatus.ok &&
      _model.status == _CheckStatus.ok &&
      _cloud.status == _CheckStatus.ok;

  bool get _stillChecking =>
      _camera.status == _CheckStatus.checking ||
      _model.status == _CheckStatus.checking ||
      _cloud.status == _CheckStatus.checking ||
      _sensor.status == _CheckStatus.checking;

  Future<void> _startSession() async {
    setState(() => _starting = true);
    try {
      final session = await _supabase.startSession();
      if (!mounted) return;
      // Replace this screen with the live session screen.
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              DashboardScreen(cameras: widget.cameras, session: session),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _starting = false);
      final offline = e.toString().contains('SocketException') ||
          e.toString().contains('Failed host lookup');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(offline
              ? 'No internet connection. Join a Wi-Fi with internet access '
                  '(not MEDS_ESP32) and try again.'
              : 'Could not start session: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Device check')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Before we start',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              "We'll quickly check your device so the session runs smoothly.",
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            FadeSlideIn(
              delay: const Duration(milliseconds: 60),
              child: _CheckRow(
                icon: Icons.camera_alt_outlined,
                title: 'Camera',
                item: _camera,
              ),
            ),
            FadeSlideIn(
              delay: const Duration(milliseconds: 140),
              child: _CheckRow(
                icon: Icons.memory,
                title: 'Emotion model',
                item: _model,
              ),
            ),
            FadeSlideIn(
              delay: const Duration(milliseconds: 220),
              child: _CheckRow(
                icon: Icons.cloud_outlined,
                title: 'Cloud connection',
                item: _cloud,
              ),
            ),
            FadeSlideIn(
              delay: const Duration(milliseconds: 300),
              child: _CheckRow(
                icon: Icons.bluetooth_connected,
                title: 'Heart-rate sensor (optional)',
                item: _sensor,
              ),
            ),
            const SizedBox(height: 20),
            if (!_stillChecking && !_requiredPassed)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade400),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'A required check failed. Please fix the issue above '
                        'and try again before starting a session.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            _ConsentCard(
              value: _consent,
              onChanged: (v) => setState(() => _consent = v ?? false),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed:
                  (_requiredPassed && _consent && !_starting && !_stillChecking)
                      ? _startSession
                      : null,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              icon: _starting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
              label: Text(_stillChecking
                  ? 'Running checks…'
                  : 'Start detection session'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final _CheckItem item;

  const _CheckRow({
    required this.icon,
    required this.title,
    required this.item,
  });

  Widget _trailing() {
    switch (item.status) {
      case _CheckStatus.checking:
        return const SizedBox(
          key: ValueKey('checking'),
          height: 18,
          width: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case _CheckStatus.ok:
        return const Icon(Icons.check_circle,
            key: ValueKey('ok'), color: MedsColors.green);
      case _CheckStatus.warn:
        return const Icon(Icons.warning_amber_rounded,
            key: ValueKey('warn'), color: MedsColors.amber);
      case _CheckStatus.fail:
        return const Icon(Icons.cancel,
            key: ValueKey('fail'), color: MedsColors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon, color: MedsColors.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(item.detail,
                      style: const TextStyle(
                          color: MedsColors.muted, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              switchInCurve: Curves.elasticOut,
              transitionBuilder: (child, anim) =>
                  ScaleTransition(scale: anim, child: child),
              child: _trailing(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConsentCard extends StatelessWidget {
  final bool value;
  final ValueChanged<bool?> onChanged;

  const _ConsentCard({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(8),
      child: CheckboxListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        controlAffinity: ListTileControlAffinity.leading,
        activeColor: MedsColors.greenDark,
        value: value,
        onChanged: onChanged,
        title: const Text('I consent to this session',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: const Text(
          'This session uses my camera (and heart-rate sensor if connected) '
          'to record emotion data to my account. I understand MEDS is for '
          'educational and wellbeing awareness only and is not a medical '
          'diagnosis.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ),
    );
  }
}
