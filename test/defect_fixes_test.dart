import 'package:flutter_test/flutter_test.dart';
import 'package:meds_flutter_no_python/models/detection_session.dart';
import 'package:meds_flutter_no_python/models/session_summary.dart';

void main() {
  final start = DateTime(2026, 9, 11, 10);
  DetectionSession session(DateTime end) => DetectionSession(
        sessionId: 's1',
        userId: 'u1',
        startTime: start,
        endTime: end,
        status: 'completed',
      );

  test('duration is never negative when the end is before the start', () {
    final s = session(start.subtract(const Duration(seconds: 16)));
    expect(s.duration, Duration.zero);
  });

  test('a session with no readings is not reported as Neutral / Calm', () {
    final s = SessionSummary.fromSession(
        session(start.add(const Duration(minutes: 2))), const []);
    expect(s.dominantEmotion, '—');
    expect(s.finalState, '—');
  });
}
