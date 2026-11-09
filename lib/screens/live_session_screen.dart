import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../models/detection_session.dart';
import '../services/ai_summary_service.dart';
import '../services/notification_router.dart';
import '../services/notification_service.dart';
import '../services/session_alert_controller.dart';
import '../services/voice_classifier.dart';
import '../theme/app_theme.dart';
import '../viewmodels/live_session_controller.dart';
import '../widgets/connection_status_cards.dart';
import '../widgets/emotion_result_cards.dart';
import '../widgets/heart_rate_card.dart';
import '../widgets/live_camera_preview_card.dart';
import '../widgets/live_insight_card.dart';
import '../widgets/meds_bottom_bar.dart';
import '../widgets/notification_bell.dart';
import '../widgets/session_alert_banner.dart';
import '../widgets/session_control_buttons.dart';
import '../widgets/session_status_banner.dart';
import '../widgets/ui_kit.dart';
import 'session_details_page.dart';

const Color _accent = Color(0xFF6A5AE0);

/// The live monitoring session. Reached after Session Readiness → Start. All
/// hardware / ML / DB work lives in [LiveSessionController].
class LiveSessionScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  final DetectionSession session;
  final ValueChanged<int> onOpenTab;
  final int? baselineBpm;
  final bool useSensor;

  const LiveSessionScreen({
    super.key,
    required this.cameras,
    required this.session,
    required this.onOpenTab,
    this.baselineBpm,
    this.useSensor = true,
  });

  @override
  State<LiveSessionScreen> createState() => _LiveSessionScreenState();
}

class _LiveSessionScreenState extends State<LiveSessionScreen>
    with WidgetsBindingObserver {
  late final LiveSessionController _c = LiveSessionController(
    cameras: widget.cameras,
    sessionId: widget.session.sessionId,
    userId: widget.session.userId,
    baselineBpm: widget.baselineBpm,
    useSensor: widget.useSensor,
  );
  bool _stopping = false;
  bool _autoPaused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _c.start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _c.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Pause recording when the app leaves the foreground; resume when it
    // returns (only if we were the ones who paused it).
    if (state == AppLifecycleState.resumed) {
      if (_autoPaused) {
        _autoPaused = false;
        _c.resume();
      }
    } else {
      if (!_c.paused && !_c.ending) {
        _autoPaused = true;
        _c.pause();
      }
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  Future<void> _confirmStop() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End Monitoring Session?'),
        content: const Text(
            'Your current session data will be saved and a session summary '
            'will be generated.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: MedsColors.red),
            child: const Text('End Session'),
          ),
        ],
      ),
    );
    if (ok == true) await _doStop();
  }

  Future<void> _doStop() async {
    setState(() => _stopping = true);
    final saved = await _c.stop();
    if (!mounted) return;
    if (!saved) {
      setState(() => _stopping = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Could not save the session. Please try again.'),
        backgroundColor: Colors.red.shade700,
      ));
      return;
    }
    // Saved and we're leaving this screen — release the camera + ML isolates
    // NOW, before the completion notification + navigation. On Android the
    // camera-HAL teardown is heavy; getting it out of the way first stops it
    // from colliding with (and stuttering) the notification sound and the
    // results-page transition.
    await _c.releaseHardware();
    if (!mounted) return;

    // Saved: confirm + (background) AI, then go to the session summary.
    await notifications.sessionCompleted(
      sessionId: widget.session.sessionId,
      userId: widget.session.userId,
    );
    unawaited(AiSummaryService().generateForSession(
      widget.session.sessionId,
      userId: widget.session.userId,
    ));
    if (!mounted) return;
    Navigator.of(context).pop(true); // back to launcher (it reloads)
    navigatorKey.currentState?.push(MaterialPageRoute(
      builder: (_) =>
          SessionDetailsPage(sessionId: widget.session.sessionId),
    ));
  }

  /// Asks "Are you OK?", records the spoken answer and reports how it sounded.
  Future<void> _voiceCheckIn() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(
      content: Text('Are you OK? Answer out loud…'),
      duration: VoiceClassifier.answerTime,
    ));
    final voice = await _c.voiceCheckIn();
    if (!mounted) return;
    messenger.hideCurrentSnackBar();
    final mismatch = _c.voiceMismatch;
    messenger.showSnackBar(SnackBar(
      content: Text(voice == null
          ? "Didn't catch that. Check the microphone permission and speak a "
              'little louder.'
          : mismatch != null
              ? 'Your voice sounds ${mismatch.toLowerCase()}. Take a moment if '
                  'you need it.'
              : 'Voice check-in: you sound ${voice.label.toLowerCase()} '
                  '(${voice.confidence.round()}%).'),
    ));
  }

  // ---- Status mapping for the small cards ---------------------------------

  ConnStatus _cameraStatus() {
    return switch (_c.alerts.cameraState) {
      IndicatorState.ok => const ConnStatus(
          label: 'Camera',
          status: 'Connected',
          color: MedsColors.greenDark,
          icon: Icons.photo_camera_outlined),
      IndicatorState.error => const ConnStatus(
          label: 'Camera',
          status: 'Permission required',
          color: MedsColors.red,
          icon: Icons.photo_camera_outlined),
      _ => const ConnStatus(
          label: 'Camera',
          status: 'Connecting',
          color: MedsColors.amber,
          icon: Icons.photo_camera_outlined),
    };
  }

  ConnStatus _sensorStatus() {
    if (!widget.useSensor) {
      return const ConnStatus(
          label: 'Sensor',
          status: 'Off',
          color: MedsColors.muted,
          icon: Icons.sensors_off);
    }
    final (status, color) = switch (_c.sensor.sensorQuality) {
      'DISCONNECTED' => ('Disconnected', MedsColors.red),
      'NO FINGER' => ('Waiting for finger', MedsColors.amber),
      'WAITING' => ('Waiting', MedsColors.amber),
      _ => ('Connected', MedsColors.greenDark),
    };
    return ConnStatus(
        label: 'Sensor',
        status: status,
        color: color,
        icon: Icons.sensors);
  }

  ConnStatus _signalStatus() {
    if (!widget.useSensor) {
      return const ConnStatus(
          label: 'Signal Quality',
          status: 'Off',
          color: MedsColors.muted,
          icon: Icons.signal_cellular_off);
    }
    final (status, color) = switch (_c.sensor.sensorQuality) {
      'GOOD' || 'HOLDING HR' => ('Good', MedsColors.greenDark),
      'WAITING' || 'NO FINGER' => ('Fair', MedsColors.amber),
      _ => ('Poor', MedsColors.red),
    };
    return ConnStatus(
        label: 'Signal Quality',
        status: status,
        color: color,
        icon: Icons.signal_cellular_alt);
  }

  String _hrStatusText() => switch (_c.sensor.sensorQuality) {
        'DISCONNECTED' => 'Sensor disconnected',
        'NO FINGER' => 'No finger detected',
        'BAD SIGNAL' => 'Signal unstable',
        'WAITING' => 'Waiting for sensor',
        _ => 'Waiting for reading',
      };

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_stopping) _confirmStop();
      },
      child: ListenableBuilder(
        listenable: _c,
        builder: (context, _) {
          final alert = _c.alerts.currentAlert;
          return Scaffold(
            body: SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  _header(),
                  const SizedBox(height: 14),
                  SessionStatusBanner(status: _c.status),
                  if (alert != null && !_c.paused) ...[
                    const SizedBox(height: 12),
                    SessionAlertBanner(
                      alert: alert,
                      onRetry: _c.retrySensor,
                      onOpenSettings: _c.retryCamera,
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 5,
                        child: LiveCameraPreviewCard(
                          controller: _c.cameraController,
                          loading: _c.loading,
                          faceVisible: _c.faceVisible,
                          paused: _c.paused,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 4,
                        child: EmotionResultCards(
                          emotion: _c.emotion.label,
                          confidence: _c.emotion.confidence,
                          state: _c.currentState,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  widget.useSensor
                      ? HeartRateCard(
                          bpm: _c.displayBpm,
                          statusText: _hrStatusText(),
                          rangeLabel: widget.baselineBpm != null
                              ? '${widget.baselineBpm! - 12}–${widget.baselineBpm! + 22} BPM'
                              : '60–100 BPM',
                          history: _c.hrHistory,
                        )
                      : const HeartRateCard(
                          bpm: null,
                          statusText: 'Heart-rate sensor off',
                          rangeLabel: 'Camera-only mode',
                          history: [],
                        ),
                  const SizedBox(height: 16),
                  ConnectionStatusCards(
                    camera: _cameraStatus(),
                    sensor: _sensorStatus(),
                    signal: _signalStatus(),
                  ),
                  const SizedBox(height: 16),
                  _sessionInfoCard(),
                  const SizedBox(height: 16),
                  LiveInsightCard(message: _c.liveInsight),
                  const SizedBox(height: 18),
                  SessionControlButtons(
                    paused: _c.paused,
                    busy: _stopping,
                    onPauseResume: () => _c.paused ? _c.resume() : _c.pause(),
                    onStop: _confirmStop,
                  ),
                ],
              ),
            ),
            floatingActionButton: SizedBox(
              width: 58,
              height: 58,
              child: FloatingActionButton(
                onPressed: _c.voiceAvailable && _c.recording && !_c.listening
                    ? _voiceCheckIn
                    : null,
                tooltip: 'Voice check-in: "Are you OK?"',
                backgroundColor:
                    _c.listening ? MedsColors.red : medsNavAccent,
                foregroundColor: Colors.white,
                elevation: 3,
                shape: const CircleBorder(),
                child: Icon(_c.listening ? Icons.graphic_eq : Icons.mic,
                    size: 26),
              ),
            ),
            floatingActionButtonLocation:
                FloatingActionButtonLocation.centerDocked,
            bottomNavigationBar: MedsBottomBar(
              index: -1, // Live flow active
              onSelect: (_) => _confirmStop(),
            ),
          );
        },
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            boxShadow: softShadow(context),
          ),
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: _accent),
            tooltip: 'Back',
            onPressed: _confirmStop,
          ),
        ),
        const Expanded(
          child: Text('Live Session',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
        ),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            boxShadow: softShadow(context),
          ),
          child: const NotificationBell(),
        ),
      ],
    );
  }

  Widget _sessionInfoCard() {
    final recording = _c.recording;
    return AppCard(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                          color: _accent.withValues(alpha: 0.12),
                          shape: BoxShape.circle),
                      child: const Icon(Icons.schedule, color: _accent, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Session Time',
                            style: TextStyle(
                                color: MedsColors.muted, fontSize: 11.5)),
                        Text(_fmt(_c.elapsed),
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                  width: 1,
                  height: 40,
                  color: Theme.of(context).dividerColor,
                  margin: const EdgeInsets.symmetric(horizontal: 8)),
              Expanded(
                child: Row(
                  children: [
                    Icon(Icons.fiber_manual_record,
                        color: recording ? MedsColors.red : MedsColors.muted,
                        size: 18),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Live Recording',
                            style: TextStyle(
                                color: MedsColors.muted, fontSize: 11.5)),
                        Text(recording ? 'Recording…' : 'Paused',
                            style: TextStyle(
                                color:
                                    recording ? MedsColors.red : MedsColors.muted,
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
                'Session ID: ${widget.session.sessionId.split('-').first}',
                style:
                    const TextStyle(color: MedsColors.muted, fontSize: 11)),
          ),
        ],
      ),
    );
  }
}
