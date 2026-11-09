import 'package:flutter/foundation.dart';

import '../models/admin_insights_model.dart';
import '../services/admin_insights_service.dart';

/// Holds the admin Insights state (period, data, loading/error) and loads it
/// through an [AdminInsightsSource]. A ChangeNotifier, matching the existing
/// view-model pattern (e.g. InsightsViewModel). It guards against overlapping
/// loads so a rapid refresh / period change can't fire duplicate requests.
class AdminInsightsViewModel extends ChangeNotifier {
  final AdminInsightsSource _source;

  AdminInsightsViewModel({AdminInsightsSource? source})
      : _source = source ?? AdminInsightsService();

  AdminInsightsPeriod _period = AdminInsightsPeriod.week;
  DateTime? _customStart;
  DateTime? _customEnd;

  AdminInsightsData? _data;
  bool _loading = false;
  bool _refreshing = false;
  Object? _error;
  bool _inFlight = false;

  AdminInsightsPeriod get period => _period;
  AdminInsightsData? get data => _data;
  bool get loading => _loading;
  bool get refreshing => _refreshing;
  Object? get error => _error;
  bool get hasData => _data?.hasData ?? false;

  /// Initial load (shows the full-screen skeleton until the first result).
  Future<void> load() => _run();

  /// Pull-to-refresh / refresh button (keeps current content, shows a spinner).
  Future<void> refresh() => _run(refreshing: true);

  /// Switches the period and reloads. [range] is required for custom.
  Future<void> setPeriod(
    AdminInsightsPeriod period, {
    DateTime? customStart,
    DateTime? customEnd,
  }) async {
    if (period == _period &&
        period != AdminInsightsPeriod.custom &&
        _data != null) {
      return;
    }
    _period = period;
    if (period == AdminInsightsPeriod.custom) {
      _customStart = customStart;
      _customEnd = customEnd;
    }
    await _run(refreshing: _data != null);
  }

  Future<void> _run({bool refreshing = false}) async {
    if (_inFlight) return; // prevent duplicated requests
    _inFlight = true;
    if (refreshing) {
      _refreshing = true;
    } else if (_data == null) {
      _loading = true;
    }
    _error = null;
    notifyListeners();

    try {
      final data = await _source.fetchInsights(
        period: _period,
        customStart: _customStart,
        customEnd: _customEnd,
      );
      _data = data;
    } catch (e) {
      _error = e;
    } finally {
      _loading = false;
      _refreshing = false;
      _inFlight = false;
      notifyListeners();
    }
  }
}
