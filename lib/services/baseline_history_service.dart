import 'supabase_service.dart';

/// Source of the user's past baselines, so the readiness flow can build a
/// *personal* resting reference instead of judging today's baseline against a
/// one-size-fits-all number. Abstracted so tests / offline runs can supply a
/// fake or omit it (null → fall back to the fixed threshold).
abstract class BaselineHistoryService {
  /// Recent completed-session baseline BPMs for the signed-in user, newest
  /// first. Empty when there's no history (or it can't be read).
  Future<List<int>> recentBaselines({int limit = 10});
}

class SupabaseBaselineHistoryService implements BaselineHistoryService {
  final SupabaseService _service;
  SupabaseBaselineHistoryService([SupabaseService? service])
      : _service = service ?? SupabaseService();

  @override
  Future<List<int>> recentBaselines({int limit = 10}) =>
      _service.fetchRecentBaselines(limit: limit);
}

/// Deterministic history for tests / demos.
class MockBaselineHistoryService implements BaselineHistoryService {
  final List<int> baselines;
  const MockBaselineHistoryService(this.baselines);

  @override
  Future<List<int>> recentBaselines({int limit = 10}) async =>
      baselines.take(limit).toList();
}
