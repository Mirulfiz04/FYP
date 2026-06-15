import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/detection_session.dart';
import '../models/emotion_result.dart';
import '../models/sensor_reading.dart';
import '../services/emotion_classifier.dart';
import '../services/esp32_sensor_service.dart';
import '../services/sensor_config.dart';
import '../services/sensor_filter.dart';
import '../services/supabase_service.dart';

class DashboardScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  final DetectionSession session;

  const DashboardScreen({
    super.key,
    required this.cameras,
    required this.session,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _classifier = EmotionClassifier();
  final _sensorService = Esp32SensorService();
  final _sensorFilter = SensorFilter();
  final _supabase = SupabaseService();

  CameraController? _cameraController;
  Timer? _emotionTimer;
  Timer? _sensorTimer;
  Timer? _saveTimer;

  EmotionResult _emotion = EmotionResult.empty;
  ProcessedSensorReading _sensor = ProcessedSensorReading.empty;

  bool _loading = true;
  bool _classifying = false;
  bool _ending = false;
  int _savedCount = 0;
  String _message = 'Starting...';

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _classifier.load();
      await _initCamera();

      _sensorTimer = Timer.periodic(const Duration(seconds: 1), (_) => _fetchSensor());
      _emotionTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) => _classifyFrame());
      _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) => _saveToSupabase());

      await _fetchSensor();
      await _classifyFrame();

      if (mounted) {
        setState(() {
          _loading = false;
          _message = 'Running';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _message = 'Startup error: $e';
        });
      }
    }
  }

  Future<void> _initCamera() async {
    if (widget.cameras.isEmpty) {
      throw Exception('No camera found');
    }

    final frontCamera = widget.cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => widget.cameras.first,
    );

    final controller = CameraController(
      frontCamera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    await controller.initialize();
    _cameraController = controller;
  }

  Future<void> _fetchSensor() async {
    try {
      final raw = await _sensorService.fetchReading();
      final processed = _sensorFilter.process(raw);
      if (mounted) {
        setState(() {
          _sensor = processed;
          _message = 'Connected to ESP32';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _sensor = ProcessedSensorReading(
            hr: _sensor.hr,
            spo2: _sensor.spo2,
            sensorQuality: 'DISCONNECTED',
            hrSource: _sensor.hrSource,
            hrQuality: 'esp32_disconnected',
            rawHr: _sensor.rawHr,
            algoHr: _sensor.algoHr,
            instantHr: _sensor.instantHr,
            sourceHr: _sensor.sourceHr,
            fixedHr: _sensor.fixedHr,
            ir: _sensor.ir,
            red: _sensor.red,
          );
          _message =
              'ESP32 not reachable. On your phone keep mobile data ON, then '
              'connect Wi-Fi to MEDS_ESP32. Sensor address: ${sensorConfig.baseUrl}';
        });
      }
    }
  }

  Future<void> _classifyFrame() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized || _classifying) return;

    _classifying = true;
    try {
      final file = await controller.takePicture();
      final length = await File(file.path).length();
      debugPrint('📸 Captured frame: ${file.path} ($length bytes)');
      final result = await _classifier.classifyImageFile(file.path);
      if (mounted) {
        setState(() {
          _emotion = result;
          _message = 'Running';
        });
      }
    } catch (e) {
      debugPrint('⚠️ classifyFrame error: $e');
      if (mounted) {
        setState(() => _message = 'Classify error: $e');
      }
    } finally {
      _classifying = false;
    }
  }

  Future<void> _saveToSupabase() async {
    if (_emotion.label == 'Detecting...') return;
    try {
      await _supabase.saveReading(
        emotion: _emotion.label,
        confidence: _emotion.confidence,
        hr: _sensor.hr,
        spo2: _sensor.spo2,
        sensorQuality: _sensor.sensorQuality,
        sessionId: widget.session.sessionId,
      );
      if (mounted) setState(() => _savedCount++);
    } catch (_) {
      // Supabase save failures are non-fatal.
    }
  }

  /// Stops capture, marks the session finished, and returns to the previous
  /// screen. Returns false if the user cancels the confirmation.
  Future<bool> _endSession() async {
    if (_ending) return false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End session?'),
        content: const Text(
            'This will stop emotion detection and close the current session.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep going')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('End session')),
        ],
      ),
    );
    if (confirmed != true) return false;

    setState(() => _ending = true);
    _emotionTimer?.cancel();
    _sensorTimer?.cancel();
    _saveTimer?.cancel();
    try {
      await _supabase.endSession(widget.session.sessionId);
    } catch (_) {
      // Closing the session record is best-effort.
    }
    if (mounted) Navigator.of(context).pop(true);
    return true;
  }

  @override
  void dispose() {
    _emotionTimer?.cancel();
    _sensorTimer?.cancel();
    _saveTimer?.cancel();
    _cameraController?.dispose();
    _classifier.close();
    super.dispose();
  }

  Color _emotionColor(String e) => switch (e) {
        'Happy' => const Color(0xFF00DC64),
        'Sad' => const Color(0xFF5578C8),
        'Angry' => const Color(0xFFFF3232),
        'Fear' => const Color(0xFF9B30FF),
        'Surprise' => const Color(0xFF00FFFF),
        'Disgust' => const Color(0xFFFFA500),
        'Neutral' => const Color(0xFFB4B4B4),
        _ => Colors.grey,
      };

  String _emotionEmoji(String e) => switch (e) {
        'Happy' => '😊',
        'Sad' => '😢',
        'Angry' => '😠',
        'Fear' => '😨',
        'Surprise' => '😲',
        'Disgust' => '🤢',
        'Neutral' => '😐',
        _ => '🔍',
      };

  Color _sensorColor(String q) => switch (q) {
        'GOOD' => const Color(0xFF00DC64),
        'HOLDING HR' => const Color(0xFF00C8FF),
        'BAD SIGNAL' => const Color(0xFFFF5050),
        'NO FINGER' => const Color(0xFFFF5050),
        'DISCONNECTED' => const Color(0xFFFF5050),
        'WAITING' => const Color(0xFFFFA500),
        _ => Colors.grey,
      };

  @override
  Widget build(BuildContext context) {
    final controller = _cameraController;
    final emotionColor = _emotionColor(_emotion.label);
    final sensorColor = _sensorColor(_sensor.sensorQuality);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _endSession();
      },
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Active Session'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh now',
            onPressed: () async {
              await _fetchSensor();
              await _classifyFrame();
            },
          ),
          TextButton.icon(
            onPressed: _ending ? null : _endSession,
            icon: const Icon(Icons.stop_circle_outlined, color: Color(0xFFFF5050)),
            label: const Text('End', style: TextStyle(color: Color(0xFFFF5050))),
          ),
        ],
      ),
      body: _loading
          ? Center(child: Text(_message, textAlign: TextAlign.center))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _SessionInfoCard(
                    session: widget.session,
                    savedCount: _savedCount,
                  ),
                  const SizedBox(height: 14),
                  if (controller != null && controller.value.isInitialized)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: AspectRatio(
                        aspectRatio: controller.value.aspectRatio,
                        child: CameraPreview(controller),
                      ),
                    )
                  else
                    _InfoCard(child: Text(_message)),
                  const SizedBox(height: 14),
                  _InfoCard(
                    child: Column(
                      children: [
                        Text(_emotionEmoji(_emotion.label), style: const TextStyle(fontSize: 70)),
                        const SizedBox(height: 6),
                        Text(
                          _emotion.label.toUpperCase(),
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.bold,
                            color: emotionColor,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 10),
                        LinearProgressIndicator(
                          value: (_emotion.confidence / 100).clamp(0.0, 1.0),
                          minHeight: 10,
                          backgroundColor: Colors.white12,
                          valueColor: AlwaysStoppedAnimation<Color>(emotionColor),
                        ),
                        const SizedBox(height: 6),
                        Text('${_emotion.confidence.toStringAsFixed(1)}% confidence'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _InfoCard(
                          child: _MetricTile(
                            icon: Icons.favorite,
                            color: const Color(0xFFFF4040),
                            value: _sensor.hr > 0 ? '${_sensor.hr}' : '---',
                            unit: 'bpm',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _InfoCard(
                          child: _MetricTile(
                            icon: Icons.water_drop,
                            color: const Color(0xFF00B4FF),
                            value: _sensor.spo2 > 0 ? '${_sensor.spo2}%' : '---%',
                            unit: 'SpO2',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _InfoCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Sensor quality', style: TextStyle(color: Colors.grey)),
                            Text(
                              _sensor.sensorQuality,
                              style: TextStyle(color: sensorColor, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'HR source: ${_sensor.hrSource} | Quality: ${_sensor.hrQuality}',
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                        Text(
                          'Raw=${_sensor.rawHr}, Algo=${_sensor.algoHr}, Inst=${_sensor.instantHr}, Source=${_sensor.sourceHr}, Fixed=${_sensor.fixedHr}',
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                        Text(
                          'IR=${_sensor.ir}, RED=${_sensor.red}',
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(_message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _ending ? null : _endSession,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFF5050),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: const Text('End Session'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Disclaimer: MEDS is for educational and wellbeing awareness '
                    'only and is not a medical diagnosis.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ],
              ),
            ),
      ),
    );
  }
}

class _SessionInfoCard extends StatelessWidget {
  final DetectionSession session;
  final int savedCount;

  const _SessionInfoCard({required this.session, required this.savedCount});

  String _fmtElapsed(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final started = DateFormat('dd MMM yyyy • HH:mm:ss').format(
      session.startTime.toLocal(),
    );
    return _InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Current session',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF00DC64).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('ACTIVE',
                    style: TextStyle(
                        color: Color(0xFF00DC64),
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        letterSpacing: 1)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _row(Icons.play_arrow, 'Started', started),
          const SizedBox(height: 6),
          _row(Icons.timer_outlined, 'Elapsed',
              _fmtElapsed(session.duration)),
          const SizedBox(height: 6),
          _row(Icons.save_alt, 'Readings saved', '$savedCount'),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
        const Spacer(),
        Text(value,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  final Widget child;
  const _InfoCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: child,
    );
  }
}

class _MetricTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String unit;

  const _MetricTile({
    required this.icon,
    required this.color,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 30),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: color)),
        Text(unit, style: const TextStyle(color: Colors.grey)),
      ],
    );
  }
}
