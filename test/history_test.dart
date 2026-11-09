import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meds_flutter_no_python/models/session_summary.dart';
import 'package:meds_flutter_no_python/services/session_repository.dart';
import 'package:meds_flutter_no_python/viewmodels/history_view_model.dart';
import 'package:meds_flutter_no_python/widgets/meds_bottom_bar.dart';
import 'package:meds_flutter_no_python/widgets/session_history_card.dart';

/// In-memory repository; [fail] can be toggled to simulate a load error.
class FakeRepo implements SessionRepository {
  List<SessionSummary> data;
  bool fail;
  FakeRepo(this.data, {this.fail = false});

  @override
  Future<List<SessionSummary>> loadSessions() async {
    if (fail) throw Exception('boom');
    return List.of(data);
  }
}

final _now = DateTime(2026, 6, 17, 12); // fixed clock for deterministic filters

SessionSummary mk({
  required String id,
  required DateTime start,
  String emotion = 'Happy',
  int avg = 78,
  AiSummaryStatus ai = AiSummaryStatus.completed,
}) {
  return SessionSummary(
    sessionId: id,
    userId: 'u',
    startTime: start,
    endTime: start.add(const Duration(minutes: 5)),
    duration: const Duration(minutes: 5),
    dominantEmotion: emotion,
    emotionConfidence: 88,
    averageBpm: avg,
    minimumBpm: avg - 10,
    maximumBpm: avg + 10,
    finalState: SessionSummary.deriveFinalState(emotion, avg),
    aiSummaryStatus: ai,
    aiSummary: null,
    status: 'completed',
    createdAt: start,
  );
}

HistoryViewModel vmFor(List<SessionSummary> data, {bool fail = false}) =>
    HistoryViewModel(repository: FakeRepo(data, fail: fail), clock: () => _now);

List<String> ids(List<SessionSummary> xs) => xs.map((e) => e.sessionId).toList();

void main() {
  test('1. sessions appear newest to oldest', () async {
    final vm = vmFor([
      mk(id: 'a', start: _now.subtract(const Duration(hours: 1))),
      mk(id: 'b', start: _now.subtract(const Duration(hours: 3))),
      mk(id: 'c', start: _now.subtract(const Duration(minutes: 10))),
    ]);
    await vm.load();
    expect(ids(vm.filtered), ['c', 'a', 'b']);
  });

  test('2. date filtering works (today / week / month)', () async {
    final vm = vmFor([
      mk(id: 'today', start: _now.subtract(const Duration(hours: 2))),
      mk(id: 'old10', start: _now.subtract(const Duration(days: 10))),
      mk(id: 'old45', start: _now.subtract(const Duration(days: 45))),
    ]);
    await vm.load();

    vm.setDateFilter(DateFilter.today);
    expect(ids(vm.filtered), ['today']);

    vm.setDateFilter(DateFilter.week);
    expect(vm.filtered.any((s) => s.sessionId == 'today'), isTrue);
    expect(vm.filtered.any((s) => s.sessionId == 'old10'), isFalse);

    vm.setDateFilter(DateFilter.month);
    expect(vm.filtered.any((s) => s.sessionId == 'today'), isTrue);
    expect(vm.filtered.any((s) => s.sessionId == 'old45'), isFalse);
  });

  test('3. search returns the correct sessions', () async {
    final vm = vmFor([
      mk(id: 'h', start: _now.subtract(const Duration(hours: 1)), emotion: 'Happy'),
      mk(id: 'a', start: _now.subtract(const Duration(hours: 2)), emotion: 'Angry'),
    ]);
    await vm.load();

    vm.setSearch('angry');
    expect(ids(vm.filtered), ['a']);

    vm.setSearch('happy');
    expect(ids(vm.filtered), ['h']);
  });

  test('4. emotion and state filters work', () async {
    final vm = vmFor([
      mk(id: 'h', start: _now.subtract(const Duration(hours: 1)), emotion: 'Happy', avg: 78),
      mk(id: 'a', start: _now.subtract(const Duration(hours: 2)), emotion: 'Angry', avg: 96),
    ]);
    await vm.load();

    vm.setFilters(const HistoryFilters(emotion: 'Angry'));
    expect(ids(vm.filtered), ['a']);

    vm.setFilters(const HistoryFilters(state: 'Calm'));
    expect(ids(vm.filtered), ['h']); // Happy + 78bpm -> Calm
  });

  test('5. summary statistics update after filtering', () async {
    final vm = vmFor([
      mk(id: 'h1', start: _now.subtract(const Duration(hours: 1)), emotion: 'Happy', avg: 70),
      mk(id: 'h2', start: _now.subtract(const Duration(hours: 2)), emotion: 'Happy', avg: 80),
      mk(id: 'a', start: _now.subtract(const Duration(hours: 3)), emotion: 'Angry', avg: 96),
    ]);
    await vm.load();

    expect(vm.summary.totalSessions, 3);
    expect(vm.summary.topEmotion, 'Happy');

    vm.setFilters(const HistoryFilters(emotion: 'Angry'));
    expect(vm.summary.totalSessions, 1);
    expect(vm.summary.topEmotion, 'Angry');
    expect(vm.summary.averageBpm, 96);
  });

  testWidgets('6. View Summary opens the correct session', (tester) async {
    final session = mk(id: 'sess-42', start: _now);
    String? tappedId;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SessionHistoryCard(
          session: session,
          onViewSummary: () => tappedId = session.sessionId,
        ),
      ),
    ));
    await tester.tap(find.text('View Summary'));
    expect(tappedId, 'sess-42');
  });

  test('7. empty state when no records exist', () async {
    final vm = vmFor([]);
    await vm.load();
    expect(vm.hasAnySessions, isFalse);
    expect(vm.filtered, isEmpty);
    expect(vm.error, isNull);
  });

  test('8. failed loading exposes an error, retry recovers', () async {
    final repo = FakeRepo([], fail: true);
    final vm = HistoryViewModel(repository: repo, clock: () => _now);
    await vm.load();
    expect(vm.error, isNotNull);
    expect(vm.hasAnySessions, isFalse);

    repo.fail = false;
    repo.data = [mk(id: 'x', start: _now)];
    await vm.refresh();
    expect(vm.error, isNull);
    expect(vm.hasAnySessions, isTrue);
  });

  test('9. AI summary status is mapped + labelled correctly', () {
    expect(AiSummaryStatus.fromRaw('completed', hasSummary: true),
        AiSummaryStatus.completed);
    expect(AiSummaryStatus.completed.label, 'AI Insight available');

    expect(AiSummaryStatus.fromRaw('processing', hasSummary: false),
        AiSummaryStatus.processing);
    expect(AiSummaryStatus.processing.label, 'Generating AI insight...');

    expect(AiSummaryStatus.fromRaw('pending', hasSummary: false).label,
        'AI insight not generated');
    expect(AiSummaryStatus.fromRaw(null, hasSummary: false),
        AiSummaryStatus.notRequested);
  });

  testWidgets('10. bottom navigation highlights History', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        bottomNavigationBar: MedsBottomBar(index: 1, onSelect: (_) {}),
      ),
    ));
    final history = tester.widget<Text>(find.text('History'));
    final home = tester.widget<Text>(find.text('Home'));
    expect(history.style?.color, medsNavAccent);
    expect(home.style?.color, medsNavMuted);
  });
}
