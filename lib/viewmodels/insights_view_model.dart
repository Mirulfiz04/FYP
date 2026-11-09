import 'package:flutter/foundation.dart';

import '../models/detection_session.dart';
import '../models/emotion_reading.dart';
import '../models/insights_data.dart';
import '../services/insights_calculator.dart';
import '../services/insights_service.dart';

enum InsightsPeriod { today, week, month, custom }

/// Holds Insights-screen state and derives [InsightsData] for the selected
/// period + granularity. A [ChangeNotifier] like the app's other controllers;
/// all calculation is delegated to [InsightsCalculator] (no UI math).
class InsightsViewModel extends ChangeNotifier {
  final InsightsSource source;
  final DateTime Function() _clock;

  InsightsViewModel({required this.source, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  bool _loading = true;
  String? _error;
  List<DetectionSession> _sessions = const [];
  List<EmotionReading> _readings = const [];

  InsightsPeriod _period = InsightsPeriod.week;
  DateTime? _customStart;
  DateTime? _customEnd;
  TrendGranularity _granularity = TrendGranularity.daily;
  InsightsData _data = InsightsData.empty;

  bool get loading => _loading;
  String? get error => _error;
  InsightsPeriod get period => _period;
  TrendGranularity get granularity => _granularity;
  InsightsData get data => _data;

  /// True when the user has at least one completed session at all (used to tell
  /// "no sessions yet" apart from "no sessions in this period").
  bool get hasAnyCompletedSession =>
      _sessions.any((s) => s.status == 'completed');

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final raw = await source.fetchRaw();
      _sessions = raw.sessions;
      _readings = raw.readings;
      _recompute();
      _loading = false;
      notifyListeners();
    } catch (_) {
      _error = 'Insights could not be loaded.';
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => load();

  void setPeriod(InsightsPeriod p, {DateTime? start, DateTime? end}) {
    _period = p;
    if (p == InsightsPeriod.custom) {
      _customStart = start;
      _customEnd = end;
    }
    _recompute();
    notifyListeners();
  }

  void setGranularity(TrendGranularity g) {
    _granularity = g;
    _recompute();
    notifyListeners();
  }

  void _recompute() {
    final (start, end) = _range();
    final span = end.difference(start);
    _data = InsightsCalculator.compute(
      sessions: _sessions,
      readings: _readings,
      start: start,
      end: end,
      prevStart: start.subtract(span),
      prevEnd: start,
      granularity: _granularity,
    );
  }

  (DateTime, DateTime) _range() {
    final now = _clock();
    switch (_period) {
      case InsightsPeriod.today:
        return (DateTime(now.year, now.month, now.day), now);
      case InsightsPeriod.week:
        final monday = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: now.weekday - 1));
        return (monday, now);
      case InsightsPeriod.month:
        return (DateTime(now.year, now.month, 1), now);
      case InsightsPeriod.custom:
        if (_customStart != null && _customEnd != null) {
          return (
            DateTime(_customStart!.year, _customStart!.month, _customStart!.day),
            DateTime(_customEnd!.year, _customEnd!.month, _customEnd!.day, 23, 59, 59),
          );
        }
        return (DateTime(now.year, now.month, now.day), now);
    }
  }
}
