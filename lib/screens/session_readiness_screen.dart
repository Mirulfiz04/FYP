import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../models/session_readiness.dart';
import '../services/baseline_emotion_probe.dart';
import '../services/baseline_history_service.dart';
import '../services/baseline_measurement_service.dart';
import '../services/device_check_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../viewmodels/session_readiness_controller.dart';
import '../widgets/meds_bottom_bar.dart';
import '../widgets/readiness_check_card.dart';
import '../widgets/readiness_status_row.dart';
import '../widgets/ui_kit.dart';
import 'live_session_screen.dart';

const Color _accent = Color(0xFF6A5AE0);

/// Pre-flight checks before a live monitoring session. Replaces the older
/// device-check screen with camera / sensor / baseline / system checks and a
/// preparation checklist; Start stays disabled until everything mandatory
/// passes ([SessionReadiness.canStartSession]).
class SessionReadinessScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  final ValueChanged<int> onOpenTab;

  const SessionReadinessScreen({
    super.key,
    required this.cameras,
    required this.onOpenTab,
  });

  @override
  State<SessionReadinessScreen> createState() => _SessionReadinessScreenState();
}

class _SessionReadinessScreenState extends State<SessionReadinessScreen> {
  late final SessionReadinessController _c = SessionReadinessController(
    deviceService: RealDeviceCheckService(widget.cameras),
    baselineService: RealBaselineMeasurementService(),
    emotionProbe: CameraEmotionProbe(widget.cameras),
    historyService: SupabaseBaselineHistoryService(),
  );
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _c.runChecks();
    // Learn the user's personal resting rate so the elevated-baseline check
    // adapts to them instead of a fixed number.
    _c.loadPersonalBaseline();
    // Keep watching the sensor so finger placement is picked up live and the
    // baseline measures automatically — no manual re-check needed.
    _c.startLiveSensorDetection();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// One-line elevated-baseline reason for the Start dialog — personalised to the
  /// user's own resting rate when we have their history.
  String _elevatedReasonShort(SessionReadiness s) {
    final bpm = s.baselineBpm;
    final usual = s.personalRestingBpm;
    if (usual != null && bpm != null) {
      return 'The baseline ($bpm BPM) is higher than your usual resting rate '
          '(~$usual BPM), so it may not reflect a calm baseline.';
    }
    return 'The baseline looks higher than a typical resting rate, so it may '
        'not reflect your true resting heart rate.';
  }

  /// Fuller elevated-baseline hint shown in the baseline card.
  String _elevatedHint(SessionReadiness s) {
    final bpm = s.baselineBpm;
    final usual = s.personalRestingBpm;
    if (usual != null && bpm != null) {
      return 'This reading ($bpm BPM) is higher than your usual resting rate '
          '(~$usual BPM from your last ${s.personalBaselineCount} sessions). '
          'If you\'re feeling tense, relax and breathe for a moment, then tap '
          'Measure Again — a calm baseline makes your stress detection more '
          'accurate.';
    }
    return 'This reading looks higher than a typical resting rate. If you\'re '
        'feeling tense, relax and breathe for a moment, then tap Measure Again '
        '— a calm baseline makes your stress detection more accurate.';
  }

  /// Tapped Start: poor signal and a missing baseline don't block, but the user
  /// should know readings may be less accurate, so we warn first and let them
  /// continue. If there's nothing to warn about we start straight away.
  Future<void> _onStartPressed() async {
    final s = _c.state;
    final warnings = <String>[
      if (s.signalQualityWarning)
        'Heart-rate signal is poor, so BPM readings may be less accurate.',
      if (s.baselineWarning)
        'No baseline BPM was captured, so the session can\'t compare your '
            'heart rate against a resting baseline.',
      if (s.baselineNotCalm)
        'You didn\'t look calm during the baseline, so the resting heart rate '
            'may be too high — stress detection works best from a calm baseline.'
      else if (s.baselineLooksElevated)
        _elevatedReasonShort(s),
    ];

    if (warnings.isNotEmpty) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.info_outline, color: MedsColors.amber),
          title: const Text('Start with warnings?'),
          content: Text(
            'You can still start the session — these are warnings only:\n\n'
            '${warnings.map((w) => '•  $w').join('\n\n')}\n\n'
            'This is normal on the emulator. Adjust your finger and re-check for '
            'a cleaner reading, or start anyway.',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _accent),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Start anyway')),
          ],
        ),
      );
      if (proceed != true) return;
    }
    await _start();
  }

  Future<void> _start() async {
    setState(() => _starting = true);
    // Free the readiness camera probe up front so the front camera is fully
    // released before the live session opens it — doing this ahead of the
    // startSession() network call gives the emulator's camera the whole
    // round-trip to close, avoiding the "Broken pipe" overlap.
    await _c.releaseCamera();
    try {
      final session = await SupabaseService().startSession();
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => LiveSessionScreen(
          cameras: widget.cameras,
          session: session,
          onOpenTab: widget.onOpenTab,
          baselineBpm: _c.state.baselineBpm,
          useSensor: _c.state.useSensor,
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _starting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not start session: $e'),
        backgroundColor: Colors.red.shade700,
      ));
    }
  }

  void _showHelp() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Session readiness'),
        content: const Text(
            'We check your camera, heart-rate sensor, a short baseline reading '
            'and storage before starting. The baseline measures automatically '
            'once your finger is on the sensor, and the camera checks you look '
            'calm so your resting heart rate is accurate. Fix any red items, '
            'complete the checklist, then tap Start Session.\n\nAmber items '
            '(poor signal, an elevated or not-calm baseline, AI or internet '
            'offline) are warnings only — they won\'t stop you, and your AI '
            'summary is generated later.'),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Got it')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _c,
          builder: (context, _) {
            final s = _c.state;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                _header(),
                const SizedBox(height: 14),
                _overallBanner(s.overall),
                const SizedBox(height: 18),
                _sensorToggleCard(s),
                _cameraCard(s),
                if (s.useSensor) ...[
                  _sensorCard(s),
                  _baselineCard(s),
                ],
                _systemCard(s),
                const SizedBox(height: 4),
                _checklistCard(s),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _c.runChecks,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _accent,
                    side: BorderSide(color: _accent.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Check Again'),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed:
                      (_c.canStart && !_starting) ? _onStartPressed : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    disabledBackgroundColor:
                        _accent.withValues(alpha: 0.35),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: _starting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.play_arrow),
                  label: const Text('Start Session',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: SizedBox(
        width: 58,
        height: 58,
        child: FloatingActionButton(
          onPressed: _c.runChecks,
          backgroundColor: medsNavAccent,
          foregroundColor: Colors.white,
          elevation: 3,
          shape: const CircleBorder(),
          tooltip: 'Re-check',
          child: const Icon(Icons.center_focus_strong, size: 26),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: MedsBottomBar(
        index: -1, // Live flow active; no list tab highlighted
        onSelect: (i) {
          Navigator.of(context).maybePop();
          widget.onOpenTab(i);
        },
      ),
    );
  }

  Widget _header() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _roundBtn(Icons.arrow_back, 'Back', () => Navigator.of(context).maybePop()),
        Expanded(
          child: Column(
            children: const [
              Text('Session Readiness',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
              SizedBox(height: 2),
              Text('Check all components before starting.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: MedsColors.muted, fontSize: 12.5)),
            ],
          ),
        ),
        _roundBtn(Icons.help_outline, 'Help', _showHelp),
      ],
    );
  }

  Widget _roundBtn(IconData icon, String tip, VoidCallback onTap) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: softShadow(context),
      ),
      child: IconButton(
          icon: Icon(icon, color: _accent), tooltip: tip, onPressed: onTap),
    );
  }

  /// Lets the user run a camera-only session (heart-rate sensor optional).
  Widget _sensorToggleCard(SessionReadiness s) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          activeThumbColor: _accent,
          value: s.useSensor,
          onChanged: _c.setUseSensor,
          secondary: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(Icons.favorite, color: _accent, size: 20),
          ),
          title: const Text('Use heart-rate sensor',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
          subtitle: Text(
            s.useSensor
                ? 'Camera + ESP32 heart-rate sensor'
                : 'Camera-only session (no heart-rate sensor)',
            style: const TextStyle(fontSize: 12, color: MedsColors.muted),
          ),
        ),
      ),
    );
  }

  Widget _overallBanner(OverallStatus status) {
    final (text, color, icon) = switch (status) {
      OverallStatus.ready => ('Ready to Start', MedsColors.greenDark, Icons.check_circle),
      OverallStatus.actionRequired =>
        ('Action Required', MedsColors.amber, Icons.error_outline),
      OverallStatus.checking =>
        ('Checking Components', MedsColors.muted, Icons.hourglass_top),
    };
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Text(text,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.bold, fontSize: 14.5)),
          ],
        ),
      ),
    );
  }

  // ---- Cards --------------------------------------------------------------

  Widget _cameraCard(SessionReadiness s) {
    return ReadinessCheckCard(
      icon: Icons.photo_camera_outlined,
      title: '1. Camera',
      rows: [
        ReadinessStatusRow(
          icon: Icons.person_outline,
          label: 'Camera Permission',
          view: ReadinessView.cameraPermission(s.cameraPermission),
          actionLabel: s.cameraPermission == CameraPermission.denied
              ? 'Allow Camera'
              : null,
          onAction: _c.retryCamera,
        ),
        ReadinessStatusRow(
          icon: Icons.videocam_outlined,
          label: 'Camera Connection',
          view: ReadinessView.cameraConnection(s.cameraConnection),
          actionLabel: s.cameraConnection == CameraConnection.unavailable
              ? 'Retry Camera'
              : null,
          onAction: _c.retryCamera,
        ),
        ReadinessStatusRow(
          icon: Icons.center_focus_weak,
          label: 'Face Visibility',
          view: ReadinessView.faceVisibility(s.faceVisibility),
        ),
      ],
    );
  }

  Widget _sensorCard(SessionReadiness s) {
    return ReadinessCheckCard(
      icon: Icons.monitor_heart_outlined,
      title: '2. Heart-Rate Sensor',
      rows: [
        ReadinessStatusRow(
          icon: Icons.sensors,
          label: 'ESP32 / Sensor',
          view: ReadinessView.sensorConnection(s.sensorConnection),
          actionLabel: s.sensorConnection == SensorConnection.disconnected
              ? 'Retry Connection'
              : null,
          onAction: _c.retrySensor,
        ),
        ReadinessStatusRow(
          icon: Icons.touch_app_outlined,
          label: 'Finger Detection',
          view: ReadinessView.fingerDetection(s.fingerDetection),
        ),
        ReadinessStatusRow(
          icon: Icons.signal_cellular_alt,
          label: 'Signal Quality',
          view: ReadinessView.signalQuality(s.signalQuality),
        ),
      ],
    );
  }

  Widget _systemCard(SessionReadiness s) {
    final CheckView internet = s.internet == NetStatus.online
        ? (text: 'Online', level: CheckLevel.ok, message: null)
        : (
            text: 'Offline',
            level: CheckLevel.warn,
            message: 'Internet isn\'t required — the session runs locally.'
          );
    return ReadinessCheckCard(
      icon: Icons.settings_outlined,
      title: '4. System',
      rows: [
        ReadinessStatusRow(
          icon: Icons.inventory_2_outlined,
          label: 'Storage / Database',
          view: ReadinessView.storage(s.storage),
        ),
        ReadinessStatusRow(
          icon: Icons.wifi,
          label: 'Internet Connection',
          view: internet,
        ),
        ReadinessStatusRow(
          icon: Icons.auto_awesome,
          label: 'AI Service',
          view: ReadinessView.aiService(s.aiService),
        ),
      ],
    );
  }

  Widget _baselineCard(SessionReadiness s) {
    final bpm = s.baselineBpm ?? s.currentBpm;
    final measuring = s.baselineStatus == BaselineStatus.measuring;
    final (statusText, color, level) = switch (s.baselineStatus) {
      BaselineStatus.notStarted => ('Not Started', MedsColors.muted, CheckLevel.idle),
      BaselineStatus.measuring => ('Measuring', MedsColors.muted, CheckLevel.checking),
      BaselineStatus.completed =>
        ('Completed', MedsColors.greenDark, CheckLevel.ok),
      // Non-blocking now: shown amber as a warning, not a red error.
      BaselineStatus.failed => ('Not Captured', MedsColors.amber, CheckLevel.warn),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(Icons.favorite, color: _accent, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('3. Baseline Measurement',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15.5)),
                ),
              ],
            ),
            Divider(height: 22, color: Theme.of(context).dividerColor),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: MedsColors.pink.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.favorite, color: MedsColors.pink, size: 22),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Baseline BPM',
                              style: TextStyle(
                                  color: MedsColors.muted, fontSize: 11)),
                          Text.rich(TextSpan(
                            text: bpm != null ? '$bpm' : '--',
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                            children: const [
                              TextSpan(
                                  text: ' BPM',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.normal,
                                      color: MedsColors.muted)),
                            ],
                          )),
                        ],
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(statusText,
                    style: TextStyle(
                        color: color, fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(width: 8),
                if (level == CheckLevel.checking)
                  const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                else if (level == CheckLevel.ok)
                  const Icon(Icons.check_circle, color: MedsColors.greenDark)
                else if (level == CheckLevel.warn)
                  const Icon(Icons.warning_amber_rounded, color: MedsColors.amber)
                else if (level == CheckLevel.error)
                  const Icon(Icons.error, color: MedsColors.red),
              ],
            ),
            if (s.personalRestingBpm != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.person_outline,
                      size: 14, color: MedsColors.muted),
                  const SizedBox(width: 6),
                  Text(
                    'Your usual resting: ~${s.personalRestingBpm} BPM '
                    '(${s.personalBaselineCount} sessions)',
                    style: const TextStyle(fontSize: 11.5, color: MedsColors.muted),
                  ),
                ],
              ),
            ],
            if (measuring) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: s.baselineProgress,
                  minHeight: 6,
                  color: _accent,
                  backgroundColor: _accent.withValues(alpha: 0.15),
                ),
              ),
              const SizedBox(height: 8),
              const Row(
                children: [
                  Icon(Icons.self_improvement, size: 15, color: MedsColors.muted),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Relax, breathe slowly and stay still — we\'re capturing '
                      'your resting heart rate.',
                      style: TextStyle(fontSize: 12, color: MedsColors.muted),
                    ),
                  ),
                ],
              ),
            ],
            if (s.baselineStatus == BaselineStatus.failed) ...[
              const SizedBox(height: 10),
              const Text(
                'Couldn\'t capture a baseline this time — this is optional and '
                'won\'t block you. For a baseline, keep your finger still on the '
                'sensor and tap Measure Again.',
                style: TextStyle(fontSize: 12, color: MedsColors.amber),
              ),
            ],
            if (s.baselineNotCalm || s.baselineLooksElevated) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: MedsColors.amber.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: MedsColors.amber.withValues(alpha: 0.4)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.tips_and_updates_outlined,
                        size: 16, color: MedsColors.amber),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        s.baselineNotCalm
                            ? 'You didn\'t look very calm just now, so this resting '
                                'reading may be too high. Relax and breathe for a '
                                'moment, then tap Measure Again — a calm baseline '
                                'makes your stress detection more accurate.'
                            : _elevatedHint(s),
                        style: const TextStyle(
                            fontSize: 12, color: MedsColors.amber),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: measuring ? null : _c.measureBaseline,
                style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                icon: const Icon(Icons.timeline),
                label: Text(s.baselineStatus == BaselineStatus.completed
                    ? 'Measure Again'
                    : 'Measure Baseline'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _checklistCard(SessionReadiness s) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.checklist, color: _accent, size: 20),
              SizedBox(width: 10),
              Text('Preparation Checklist',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5)),
            ],
          ),
          const SizedBox(height: 4),
          ...s.requiredPrepItems.map((item) => CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: _accent,
                value: s.prepConfirmed.contains(item.key),
                onChanged: (v) => _c.togglePrep(item.key, v ?? false),
                title: Text(item.label, style: const TextStyle(fontSize: 13.5)),
              )),
        ],
      ),
    );
  }
}
