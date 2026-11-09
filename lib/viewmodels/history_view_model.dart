import 'package:flutter/foundation.dart';

import '../models/session_summary.dart';
import '../services/session_repository.dart';

enum DateFilter { today, week, month, custom }

/// Advanced (sheet) filters. All optional and combined with AND.
class HistoryFilters {
  final String? emotion;
  final String? state;
  final int? minBpm;
  final int? maxBpm;
  final bool aiAvailableOnly;
  final String? status;

  const HistoryFilters({
    this.emotion,
    this.state,
    this.minBpm,
    this.maxBpm,
    this.aiAvailableOnly = false,
    this.status,
  });

  bool get isEmpty =>
      emotion == null &&
      state == null &&
      minBpm == null &&
      maxBpm == null &&
      !aiAvailableOnly &&
      status == null;

  int get activeCount => [
        emotion != null,
        state != null,
        minBpm != null,
        maxBpm != null,
        aiAvailableOnly,
        status != null,
      ].where((b) => b).length;

  HistoryFilters copyWith({
    Object? emotion = _unset,
    Object? state = _unset,
    Object? minBpm = _unset,
    Object? maxBpm = _unset,
    bool? aiAvailableOnly,
    Object? status = _unset,
  }) {
    return HistoryFilters(
      emotion: emotion == _unset ? this.emotion : emotion as String?,
      state: state == _unset ? this.state : state as String?,
      minBpm: minBpm == _unset ? this.minBpm : minBpm as int?,
      maxBpm: maxBpm == _unset ? this.maxBpm : maxBpm as int?,
      aiAvailableOnly: aiAvailableOnly ?? this.aiAvailableOnly,
      status: status == _unset ? this.status : status as String?,
    );
  }
}

const Object _unset = Object();

/// Aggregates shown in the summary overview card, recomputed for the current
/// filtered set.
class HistorySummary {
  final int totalSessions;
  final int averageBpm;
  final String topEmotion;
  final int topEmotionPercent;

  const HistorySummary({
    required this.totalSessions,
    required this.averageBpm,
    required this.topEmotion,
    required this.topEmotionPercent,
  });

  static const empty = HistorySummary(
    totalSessions: 0,
    averageBpm: 0,
    topEmotion: '—',
    topEmotionPercent: 0,
  );
}

/// Holds and derives all History-screen state. A [ChangeNotifier] like the
/// app's other controllers; the UI listens via [ListenableBuilder]. All
/// filtering/search/pagination lives here, not in widgets.
class HistoryViewModel extends ChangeNotifier {
  final SessionRepository repository;
  final DateTime Function() _clock;
  final int pageSize;

  HistoryViewModel({
    required this.repository,
    DateTime Function()? clock,
    this.pageSize = 10,
  }) : _clock = clock ?? DateTime.now;

  bool _loading = false;
  String? _error;
  List<SessionSummary> _all = [];

  DateFilter _dateFilter = DateFilter.today;
  DateTime? _customStart;
  DateTime? _customEnd;
  String _search = '';
  HistoryFilters _filters = const HistoryFilters();
  int _visibleCount = 10;

  // ---- Read-only state ----------------------------------------------------
  bool get loading => _loading;
  String? get error => _error;
  DateFilter get dateFilter => _dateFilter;
  String get search => _search;
  HistoryFilters get filters => _filters;
  bool get hasAnySessions => _all.isNotEmpty;

  List<SessionSummary> get filtered {
    final range = _range();
    final q = _search.trim();
    final f = _filters;
    final list = _all.where((s) {
      final t = s.startTime;
      if (range != null && (t.isBefore(range.$1) || t.isAfter(range.$2))) {
        return false;
      }
      if (q.isNotEmpty && !s.matches(q)) return false;
      if (f.emotion != null && s.dominantEmotion != f.emotion) return false;
      if (f.state != null && s.finalState != f.state) return false;
      if (f.minBpm != null && s.averageBpm < f.minBpm!) return false;
      if (f.maxBpm != null && s.averageBpm > f.maxBpm!) return false;
      if (f.aiAvailableOnly && !s.aiSummaryStatus.isAvailable) return false;
      if (f.status != null && s.status != f.status) return false;
      return true;
    }).toList();
    // Already sorted newest-first in [load]; keep that order.
    return list;
  }

  List<SessionSummary> get visible =>
      filtered.take(_visibleCount).toList(growable: false);

  bool get hasMore => filtered.length > _visibleCount;

  HistorySummary get summary {
    final list = filtered;
    if (list.isEmpty) return HistorySummary.empty;
    final hr = list.where((s) => s.averageBpm > 0).map((s) => s.averageBpm);
    final avg = hr.isEmpty ? 0 : (hr.reduce((a, b) => a + b) / hr.length).round();
    final counts = <String, int>{};
    for (final s in list) {
      counts[s.dominantEmotion] = (counts[s.dominantEmotion] ?? 0) + 1;
    }
    final top = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return HistorySummary(
      totalSessions: list.length,
      averageBpm: avg,
      topEmotion: top.key,
      topEmotionPercent: (top.value * 100 / list.length).round(),
    );
  }

  // ---- Mutations ----------------------------------------------------------

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final data = await repository.loadSessions();
      data.sort((a, b) => b.startTime.compareTo(a.startTime)); // newest first
      _all = data;
      _loading = false;
      notifyListeners();
    } catch (e) {
      _all = [];
      _error = 'Session history could not be loaded.';
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => load();

  void setDateFilter(DateFilter f, {DateTime? start, DateTime? end}) {
    _dateFilter = f;
    if (f == DateFilter.custom) {
      _customStart = start;
      _customEnd = end;
    }
    _resetPaging();
    notifyListeners();
  }

  void setSearch(String value) {
    _search = value;
    _resetPaging();
    notifyListeners();
  }

  void setFilters(HistoryFilters f) {
    _filters = f;
    _resetPaging();
    notifyListeners();
  }

  void clearFilters() {
    _filters = const HistoryFilters();
    _search = '';
    _resetPaging();
    notifyListeners();
  }

  void loadMore() {
    if (!hasMore) return;
    _visibleCount += pageSize;
    notifyListeners();
  }

  void _resetPaging() => _visibleCount = pageSize;

  /// Inclusive [start, end] window for the active date filter, or null for "all".
  (DateTime, DateTime)? _range() {
    final now = _clock();
    final endOfNow = now;
    switch (_dateFilter) {
      case DateFilter.today:
        return (DateTime(now.year, now.month, now.day), endOfNow);
      case DateFilter.week:
        final monday = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: now.weekday - 1));
        return (monday, endOfNow);
      case DateFilter.month:
        return (DateTime(now.year, now.month, 1), endOfNow);
      case DateFilter.custom:
        if (_customStart == null || _customEnd == null) return null;
        final s = DateTime(
            _customStart!.year, _customStart!.month, _customStart!.day);
        final e = DateTime(_customEnd!.year, _customEnd!.month, _customEnd!.day,
            23, 59, 59);
        return (s, e);
    }
  }
}
