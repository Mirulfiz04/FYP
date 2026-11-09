import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../services/session_details_service.dart';

/// Holds Session Details state and the review/delete/export actions. A
/// [ChangeNotifier]; all analytics are computed in the service, never in build.
class SessionDetailsController extends ChangeNotifier {
  final SessionDetailsService service;
  final String sessionId;

  /// How often to re-check for the AI summary while it's still generating, and a
  /// safety cap so we never poll forever.
  final Duration aiPollInterval;
  static const int _aiPollMaxTicks = 40;

  SessionDetailsController({
    required this.service,
    required this.sessionId,
    this.aiPollInterval = const Duration(seconds: 3),
  });

  bool _loading = true;
  bool _busy = false;
  bool _disposed = false;
  String? _error;
  SessionDetailsData? _data;
  Timer? _aiPoll;
  int _aiPollTicks = 0;

  bool get loading => _loading;
  bool get busy => _busy;
  String? get error => _error;
  SessionDetailsData? get data => _data;
  bool get isAdmin => _data?.viewerIsAdmin ?? false;
  bool get flaggedForReview => _data?.session.flaggedForReview ?? false;

  /// True while the AI summary is still being generated (so the UI shows the
  /// "Generating…" state and we keep polling for it).
  bool get aiPending {
    final s = _data?.session;
    if (s == null || s.aiSummary != null) return false;
    return s.aiSummaryStatus == 'pending' || s.aiSummaryStatus == 'processing';
  }

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _data = await service.load(sessionId);
      _loading = false;
      notifyListeners();
      _syncAiPolling();
    } catch (_) {
      _error = 'Could not load this session.';
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => load();

  // ---- AI-summary polling -------------------------------------------------
  // The insight is generated in the background after the session ends, so when
  // the page opens it may still be "processing". We poll the session row until
  // it's ready and update in place — no need to leave and re-open the page.

  void _syncAiPolling() {
    if (aiPending) {
      _aiPoll ??= Timer.periodic(aiPollInterval, (_) => _pollAi());
    } else {
      _stopAiPolling();
    }
  }

  void _stopAiPolling() {
    _aiPoll?.cancel();
    _aiPoll = null;
  }

  Future<void> _pollAi() async {
    if (_disposed || !aiPending || _aiPollTicks >= _aiPollMaxTicks) {
      _stopAiPolling();
      return;
    }
    _aiPollTicks++;
    try {
      final session = await service.reloadSession(sessionId);
      if (_disposed) return;
      _data = _data?.copyWith(session: session);
      notifyListeners();
      if (!aiPending) _stopAiPolling();
    } catch (_) {
      // Transient — keep trying until the cap.
    }
  }

  /// Toggles "flagged for review" and reloads on success.
  Future<bool> toggleReview() async {
    if (_busy) return false;
    _busy = true;
    notifyListeners();
    final ok = await service.setReview(sessionId, !flaggedForReview);
    if (ok) await load();
    _busy = false;
    notifyListeners();
    return ok;
  }

  Future<bool> deleteSession() async {
    if (_busy) return false;
    _busy = true;
    notifyListeners();
    final ok = await service.delete(sessionId);
    _busy = false;
    notifyListeners();
    return ok;
  }

  /// A compact, shareable text report (no raw per-reading dump).
  String reportText() {
    final d = _data;
    if (d == null) return 'No session data.';
    final s = d.session;
    final a = d.analytics;
    final fmtDate = DateFormat('dd MMM yyyy');
    final fmtTime = DateFormat('h:mm:ss a');
    final dur = s.endTime != null
        ? s.endTime!.difference(s.startTime)
        : Duration.zero;
    final hr = a.hasValidHr
        ? 'Avg ${a.avgBpm} BPM (min ${a.minBpm}, max ${a.maxBpm})'
        : 'No valid heart-rate data';

    final buf = StringBuffer()
      ..writeln('MEDS — Session Report')
      ..writeln('Session ID: ${s.sessionId}')
      ..writeln('Status: ${s.status}')
      ..writeln('Date: ${fmtDate.format(s.startTime.toLocal())}')
      ..writeln('Started: ${fmtTime.format(s.startTime.toLocal())}')
      ..writeln(s.endTime != null
          ? 'Ended: ${fmtTime.format(s.endTime!.toLocal())}'
          : 'Ended: —')
      ..writeln('Duration: ${dur.inMinutes}m ${dur.inSeconds.remainder(60)}s')
      ..writeln('')
      ..writeln('Dominant emotion: ${a.dominantEmotion} '
          '(${a.dominantPercent}%, ${a.dominantCount} of ${a.totalReadings})')
      ..writeln('Heart rate: $hr')
      ..writeln('Stress indicator: ${a.stressIndicator} (wellness indicator)')
      ..writeln('Avg face confidence: ${a.avgConfidence}%')
      ..writeln('Valid HR readings: ${a.validHrCount} of ${a.totalReadings}')
      ..writeln('Session reliability: ${a.reliability}');

    if (s.aiSummary != null) {
      buf
        ..writeln('')
        ..writeln('AI insight: ${s.aiSummary!.emotionalSummary}');
    }
    buf
      ..writeln('')
      ..writeln('Generated by MEDS — for wellness self-awareness only, not a '
          'medical diagnosis.');
    return buf.toString();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopAiPolling();
    super.dispose();
  }
}
