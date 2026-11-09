import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/detection_session.dart';
import '../models/emotion_result.dart';
import '../models/multimodal_result.dart';
import '../models/sensor_reading.dart';
import '../services/ai_summary_service.dart';
import '../services/emotion_classifier.dart';
import '../services/emotion_fusion.dart';
import '../services/sensor_service.dart';
import '../services/notification_router.dart';
import '../services/notification_service.dart';
import '../services/sensor_config.dart';
import '../services/sensor_filter.dart';
import '../services/session_alert_controller.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_fun.dart';
import '../widgets/session_alert_banner.dart';
import '../widgets/ui_kit.dart';
import 'sessions_screen.dart';

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
  final _sensorService = createSensorService();
  final _sensorFilter = SensorFilter();
  final _supabase = SupabaseService();
  final _fusion = EmotionFusion();
  final _alerts = SessionAlertController();

  /// Minimum confidence (%) for a frame to count as a clearly visible face.
  static const double _faceConfidenceThreshold = 35;

  CameraController? _cameraController;
  Timer? _emotionTimer;
  Timer? _sensorTimer;
  Timer? _saveTimer;

  EmotionResult _emotion = EmotionResult.empty;
  ProcessedSensorReading _sensor = ProcessedSensorReading.empty;
  MultimodalResult? _multi;

  bool _loading = true;
  bool _classifying = false;
  bool _ending = false;
  bool _disposed = false;
  int _savedCount = 0;
  int _celebrate = 0; // bumped to fire confetti on a fresh happy moment
  String _message = 'Starting...';

  // ---- Gamified "vibe" tracking for the current session -------------------
  int _vibeScore = 0; // points earned this session
  int _streak = 0; // consecutive positive detections
  int _bestStreak = 0;
  int _positiveCount = 0;
  int _detectionCount = 0;
  final Map<String, int> _emotionTally = {};

  // ---- Multimodal (face + heart rate) tracking ----------------------------
  final Map<String, int> _wellbeingTally = {};
  int _elevatedArousalCount = 0;
  int _peakHrDelta = 0;

  static const _positiveEmotions = {'Happy', 'Surprise'};

  /// Updates the running vibe score/streak from a fresh classification.
  void _updateVibe(EmotionResult r) {
    if (r.label == 'Detecting...') return;
    _detectionCount++;
    _emotionTally[r.label] = (_emotionTally[r.label] ?? 0) + 1;

    final base = switch (r.label) {
      'Happy' => 10,
      'Surprise' => 7,
      'Neutral' => 3,
      _ => 1,
    };

    if (_positiveEmotions.contains(r.label)) {
      _streak++;
      _positiveCount++;
      if (_streak > _bestStreak) _bestStreak = _streak;
    } else {
      _streak = 0;
    }
    // Reward streaks: each positive in a row adds a small bonus (capped).
    _vibeScore += base + (_streak.clamp(0, 10));
  }

  int get _positivityPct =>
      _detectionCount == 0 ? 0 : (_positiveCount * 100 / _detectionCount).round();

  String _vibeTitle(int pct) {
    if (pct >= 80) return 'Radiant ✨';
    if (pct >= 60) return 'Upbeat 😄';
    if (pct >= 40) return 'Balanced 🙂';
    if (pct >= 20) return 'Reflective 🤔';
    return 'Take it easy 💙';
  }

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _classifier.load();
      await _initCamera();
      if (!mounted) return;

      _alerts.setCameraReady();
      _alerts.setAiAvailable(true); // key lives server-side in ai-proxy

      // Show the live camera preview straight away. We must NOT block on the
      // first (heavy) classification here: on slower devices that capture +
      // inference can take a second or more, and gating the loading flag on it
      // left the screen stuck on "Connected to ESP32" with no preview.
      setState(() {
        _loading = false;
        _message = 'Running';
      });

      _sensorTimer =
          Timer.periodic(const Duration(seconds: 1), (_) => _fetchSensor());
      _emotionTimer = Timer.periodic(
          const Duration(milliseconds: 1500), (_) => _classifyFrame());
      _saveTimer =
          Timer.periodic(const Duration(seconds: 5), (_) => _saveToSupabase());

      // Kick off the first sensor read immediately. The first classification is
      // left to the 1.5s timer so the camera has a moment to settle — capturing
      // a still in the instant after initialize() can hang on some devices.
      unawaited(_fetchSensor());
    } catch (e) {
      final code = e is CameraException ? e.code.toLowerCase() : '';
      final permissionDenied = code.contains('access') ||
          code.contains('permission') ||
          code.contains('denied');
      if (permissionDenied) _alerts.setCameraPermissionRequired();
      if (mounted) {
        setState(() {
          _loading = false;
          _message = permissionDenied
              ? 'Camera permission is required for facial-emotion detection.'
              : 'Startup error: $e';
        });
      }
    }
  }

  /// Re-attempts camera initialization — used by the "Allow Camera" action when
  /// permission was denied. Re-running initialize() re-triggers the OS prompt.
  Future<void> _retryCamera() async {
    try {
      await _cameraController?.dispose();
      _cameraController = null;
      await _initCamera();
      if (!mounted) return;
      _alerts.setCameraReady();
      setState(() => _message = 'Running');
    } catch (e) {
      final code = e is CameraException ? e.code.toLowerCase() : '';
      if (code.contains('access') ||
          code.contains('permission') ||
          code.contains('denied')) {
        _alerts.setCameraPermissionRequired();
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

    // Low resolution on purpose: the model only sees a 224x224 crop, and a
    // smaller capture makes takePicture + JPEG decode dramatically faster,
    // which keeps the UI thread responsive (avoids the "isn't responding" ANR).
    final controller = CameraController(
      frontCamera,
      ResolutionPreset.low,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    await controller.initialize();

    // If the screen was torn down while the camera was still initializing,
    // dispose the freshly-created controller instead of keeping it — otherwise
    // the plugin's late "initialized" callback fires on a disposed controller
    // and crashes the app with an unhandled exception.
    if (_disposed || !mounted) {
      await controller.dispose();
      return;
    }
    _cameraController = controller;
  }

  Future<void> _fetchSensor() async {
    try {
      final raw = await _sensorService.fetchReading();
      final processed = _sensorFilter.process(raw);
      _alerts.onSensorQuality(processed.sensorQuality);
      if (mounted) {
        setState(() {
          _sensor = processed;
          _message = 'Connected to ESP32';
        });
      }
    } catch (e) {
      _alerts.onSensorQuality('DISCONNECTED');
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
    if (_disposed ||
        controller == null ||
        !controller.value.isInitialized ||
        _classifying) {
      return;
    }

    _classifying = true;
    try {
      // Cap the capture: on some devices takePicture() can hang indefinitely,
      // which would leave _classifying stuck true and freeze detection on
      // "DETECTING…" forever. A timeout lets the next tick retry instead.
      final file =
          await controller.takePicture().timeout(const Duration(seconds: 5));
      // The session may have ended (controller disposed) while we awaited.
      if (_disposed || !mounted) return;
      final length = await File(file.path).length();
      debugPrint('📸 Captured frame: ${file.path} ($length bytes)');
      final result = await _classifier.classifyImageFile(file.path);
      if (_disposed || !mounted) return;

      // Drive the "face not clearly visible" detector: an empty or very
      // low-confidence result means we couldn't read a face this frame.
      _alerts.onFrame(
        faceVisible: result.probabilities.isNotEmpty &&
            result.confidence >= _faceConfidenceThreshold,
      );

      // Multimodal fusion: smooth the facial result and let the latest heart
      // rate corroborate it. Skip when there's no facial result yet (the camera
      // is still warming up) so we keep showing "Detecting…".
      final fused = result.probabilities.isEmpty
          ? null
          : _fusion.process(result, _classifier.labels, _sensor);
      final display = fused?.emotion ?? result;

      // Celebrate a fresh, confident happy/surprise moment with confetti.
      final wasHappy = _emotion.label == 'Happy' || _emotion.label == 'Surprise';
      final isHappy = display.label == 'Happy' || display.label == 'Surprise';
      final celebrateNow = isHappy && !wasHappy && display.confidence >= 50;
      final labelChanged =
          display.label != _emotion.label && display.label != 'Detecting...';

      // Tactile feedback: a celebratory buzz for happy moments, a gentle
      // tick when the detected emotion simply changes.
      if (celebrateNow) {
        HapticFeedback.heavyImpact();
        SystemSound.play(SystemSoundType.alert);
      } else if (labelChanged) {
        HapticFeedback.selectionClick();
      }

      if (fused != null) {
        _wellbeingTally[fused.wellbeing] =
            (_wellbeingTally[fused.wellbeing] ?? 0) + 1;
        if (fused.arousal == Arousal.elevated || fused.arousal == Arousal.high) {
          _elevatedArousalCount++;
        }
        if (fused.hrDelta > _peakHrDelta) _peakHrDelta = fused.hrDelta;
      }

      _updateVibe(display);

      setState(() {
        _emotion = display;
        _multi = fused;
        _message = 'Running';
        if (celebrateNow) _celebrate++;
      });
    } catch (e) {
      debugPrint('⚠️ classifyFrame error: $e');
      // Ignore failures caused by the controller being torn down when the
      // session ends; only surface a real error while still on screen.
      if (!_disposed && mounted) {
        _alerts.onFrame(faceVisible: false);
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

    var saved = false;
    try {
      await _supabase.endSession(widget.session.sessionId);
      saved = true;
    } catch (_) {
      // Closing the session record failed — do NOT claim completion.
    }

    if (saved) {
      final uid = widget.session.userId;
      // In-app confirmation is the summary dialog below; this also persists a
      // notification + (background-capable) local notification.
      await notifications.sessionCompleted(
        sessionId: widget.session.sessionId,
        userId: uid,
      );
      // Generate the AI insight in the background; it notifies when the status
      // becomes completed (or failed). Not awaited so we return promptly.
      unawaited(AiSummaryService()
          .generateForSession(widget.session.sessionId, userId: uid));
    }

    var viewSummary = false;
    if (mounted) viewSummary = await _showSummary(saved: saved);
    if (mounted) Navigator.of(context).pop(true);
    if (viewSummary) {
      navigatorKey.currentState?.push(MaterialPageRoute(
        builder: (_) =>
            SessionDetailLoaderScreen(sessionId: widget.session.sessionId),
      ));
    }
    return true;
  }

  /// A celebratory recap of how the session went (score, streak, mood).
  /// Returns true if the user chose "View Summary".
  Future<bool> _showSummary({required bool saved}) async {
    if (_detectionCount == 0) return false;
    final dominant = _emotionTally.entries.fold<MapEntry<String, int>?>(
      null,
      (best, e) => best == null || e.value > best.value ? e : best,
    );
    final domLabel = dominant?.key ?? 'Neutral';

    // Dominant multimodal wellbeing state across the whole session.
    final domWellbeing = _wellbeingTally.entries
        .fold<MapEntry<String, int>?>(
          null,
          (best, e) => best == null || e.value > best.value ? e : best,
        )
        ?.key;
    final wbTotal = _wellbeingTally.values.fold<int>(0, (a, b) => a + b);
    final elevatedPct =
        wbTotal == 0 ? 0 : (_elevatedArousalCount * 100 / wbTotal).round();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Session complete 🎉'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (saved)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Your monitoring session has been completed. The session '
                  'summary is ready.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: Colors.grey),
                ),
              ),
            Text(_emotionEmoji(domLabel), style: const TextStyle(fontSize: 56)),
            const SizedBox(height: 2),
            Text(
              'Mostly $domLabel',
              style: TextStyle(
                color: _emotionColor(domLabel),
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            if (domWellbeing != null) ...[
              const SizedBox(height: 14),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: _wellbeingColor(domWellbeing).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_wellbeingEmoji(domWellbeing),
                        style: const TextStyle(fontSize: 26)),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Overall: $domWellbeing',
                          style: TextStyle(
                            color: _wellbeingColor(domWellbeing),
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const Text(
                          'Face + heart rate combined',
                          style: TextStyle(color: Colors.grey, fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            _summaryRow('Vibe score', '$_vibeScore'),
            _summaryRow('Best streak', '$_bestStreak in a row'),
            _summaryRow('Positivity', '$_positivityPct%'),
            if (wbTotal > 0) _summaryRow('Elevated arousal', '$elevatedPct%'),
            if (_peakHrDelta > 0)
              _summaryRow('Peak HR rise', '+$_peakHrDelta bpm'),
            _summaryRow('Readings saved', '$_savedCount'),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF00DC64).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _vibeTitle(_positivityPct),
                style: const TextStyle(
                    color: Color(0xFF00DC64), fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        actions: [
          if (saved)
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('View Summary'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // Flag first so any in-flight classify/sensor callback bails out instead of
    // touching the controller or interpreter we are about to tear down.
    _disposed = true;
    _emotionTimer?.cancel();
    _sensorTimer?.cancel();
    _saveTimer?.cancel();
    _cameraController?.dispose();
    _classifier.close();
    _alerts.dispose();
    super.dispose();
  }

  Color _emotionColor(String e) => MedsColors.emotion(e);

  String _emotionEmoji(String e) => MedsColors.emoji(e);

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
                  ListenableBuilder(
                    listenable: _alerts,
                    builder: (context, _) {
                      final alert = _alerts.currentAlert;
                      return Column(
                        children: [
                          StatusIndicatorRow(
                            camera: _alerts.cameraState,
                            sensor: _alerts.sensorState,
                            ai: _alerts.aiState,
                          ),
                          if (alert != null) ...[
                            const SizedBox(height: 12),
                            SessionAlertBanner(
                              alert: alert,
                              onRetry: _fetchSensor,
                              onOpenSettings: _retryCamera,
                            ),
                          ],
                          const SizedBox(height: 14),
                        ],
                      );
                    },
                  ),
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
                  Stack(
                    alignment: Alignment.topCenter,
                    children: [
                      _InfoCard(
                        child: Column(
                          children: [
                            PulseGlow(
                              color: emotionColor,
                              child: AnimatedEmoji(
                                emoji: _emotionEmoji(_emotion.label),
                              ),
                            ),
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
                            const SizedBox(height: 12),
                            _ConfidenceBar(
                              value: (_emotion.confidence / 100).clamp(0.0, 1.0),
                              color: emotionColor,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${_emotion.confidence.toStringAsFixed(1)}% confidence',
                            ),
                          ],
                        ),
                      ),
                      Positioned.fill(
                        child: ConfettiBurst(trigger: _celebrate),
                      ),
                    ],
                  ),
                  if (_multi != null) ...[
                    const SizedBox(height: 12),
                    _WellbeingCard(result: _multi!),
                  ],
                  const SizedBox(height: 12),
                  _VibeCard(
                    score: _vibeScore,
                    streak: _streak,
                    positivityPct: _positivityPct,
                    title: _vibeTitle(_positivityPct),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _InfoCard(
                          child: _MetricTile(
                            icon: Icons.favorite,
                            iconWidget: PulsingHeart(
                              bpm: _sensor.hr,
                              color: const Color(0xFFFF4040),
                              size: 30,
                            ),
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
              const Pill(
                  text: 'ACTIVE', color: medsGreen, icon: Icons.sensors),
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
  Widget build(BuildContext context) =>
      AppCard(padding: const EdgeInsets.all(18), child: child);
}

/// The multimodal read-out: the combined wellbeing state (from facial valence ×
/// heart-rate arousal) and how the current HR compares to the session baseline.
Color _wellbeingColor(String wb) => switch (wb) {
      'Excited' => const Color(0xFFFFA500),
      'Content' => const Color(0xFF00DC64),
      'Calm' => const Color(0xFF00C8FF),
      'Relaxed' => const Color(0xFF00C8A0),
      'Alert' => const Color(0xFFFFC400),
      'Stressed' => const Color(0xFFFF5050),
      'Down' => const Color(0xFF9B30FF),
      _ => Colors.grey,
    };

String _wellbeingEmoji(String wb) => switch (wb) {
      'Excited' => '🤩',
      'Content' => '😊',
      'Calm' => '🙂',
      'Relaxed' => '😌',
      'Alert' => '😯',
      'Stressed' => '😣',
      'Down' => '😔',
      _ => '🙂',
    };

class _WellbeingCard extends StatelessWidget {
  final MultimodalResult result;
  const _WellbeingCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final color = _wellbeingColor(result.wellbeing);
    final sign = result.hrDelta >= 0 ? '+' : '';
    final arousalText = result.baselineReady
        ? '${result.arousalLabel} arousal · $sign${result.hrDelta} bpm vs baseline'
        : 'Learning your baseline heart rate…';

    return _InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome, size: 16, color: MedsColors.purple),
              SizedBox(width: 6),
              Text(
                'MULTIMODAL READ',
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(result.wellbeingEmoji, style: const TextStyle(fontSize: 38)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.wellbeing,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Face + heart rate combined',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.monitor_heart_outlined, size: 14, color: color),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    arousalText,
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final IconData icon;
  final Widget? iconWidget;
  final Color color;
  final String value;
  final String unit;

  const _MetricTile({
    required this.icon,
    required this.color,
    required this.value,
    required this.unit,
    this.iconWidget,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 32,
          child: Center(
            child: iconWidget ?? Icon(icon, color: color, size: 30),
          ),
        ),
        const SizedBox(height: 8),
        // Number grows/shrinks smoothly as the reading changes.
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          transitionBuilder: (child, anim) =>
              ScaleTransition(scale: anim, child: child),
          child: Text(
            value,
            key: ValueKey(value),
            style: TextStyle(
                fontSize: 30, fontWeight: FontWeight.bold, color: color),
          ),
        ),
        Text(unit, style: const TextStyle(color: Colors.grey)),
      ],
    );
  }
}

/// Gamified "vibe" card: a live score, a positivity read-out and a streak
/// badge that grows hotter the longer you stay positive.
class _VibeCard extends StatelessWidget {
  final int score;
  final int streak;
  final int positivityPct;
  final String title;

  const _VibeCard({
    required this.score,
    required this.streak,
    required this.positivityPct,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            const Color(0xFF00DC64).withValues(alpha: 0.16),
            const Color(0xFF9B30FF).withValues(alpha: 0.16),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '⚡ VIBE SCORE',
                  style: TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 2),
                AnimatedCount(
                  value: score,
                  style: const TextStyle(
                      fontSize: 34, fontWeight: FontWeight.bold),
                ),
                Text(
                  '$title  ·  $positivityPct% positive',
                  style: const TextStyle(color: Colors.grey, fontSize: 12.5),
                ),
              ],
            ),
          ),
          _StreakBadge(streak: streak),
        ],
      ),
    );
  }
}

class _StreakBadge extends StatelessWidget {
  final int streak;
  const _StreakBadge({required this.streak});

  @override
  Widget build(BuildContext context) {
    final active = streak >= 2;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedScale(
          scale: active ? (1.0 + (streak.clamp(0, 12) * 0.05)) : 0.85,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          child: Opacity(
            opacity: active ? 1.0 : 0.35,
            child: const Text('🔥', style: TextStyle(fontSize: 30)),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          active ? '$streak in a row' : 'Streak',
          style: TextStyle(
            color: active ? const Color(0xFFFFA500) : Colors.grey,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

/// A rounded confidence bar that animates smoothly toward [value] (0..1) and
/// uses a subtle gradient in the emotion's colour.
class _ConfidenceBar extends StatelessWidget {
  final double value;
  final Color color;

  const _ConfidenceBar({required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 12,
        color: color.withValues(alpha: 0.15),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => FractionallySizedBox(
              widthFactor: v.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      color.withValues(alpha: 0.6),
                      color,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
