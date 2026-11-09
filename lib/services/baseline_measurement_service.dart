import '../models/emotion_result.dart';
import '../models/session_readiness.dart';
import 'baseline_emotion_probe.dart';
import 'sensor_filter.dart';
import 'sensor_service.dart';

/// The outcome of a baseline measurement: the resting BPM (when [ok]) plus, when
/// a camera probe was supplied, whether the user looked [calmness] calm while it
/// was taken.
typedef BaselineResult = ({bool ok, int? bpm, BaselineCalmness calmness});

/// Collects a baseline heart rate by averaging several stable readings (never
/// trusting a single sample). Swap [RealBaselineMeasurementService] for
/// [MockBaselineMeasurementService] in tests / without hardware.
abstract class BaselineMeasurementService {
  /// [onTick] reports the latest BPM and progress (0..1) as samples arrive.
  /// [emotionProbe], when given, is sampled in parallel to judge calmness.
  Future<BaselineResult> measure({
    void Function(int currentBpm, double progress)? onTick,
    BaselineEmotionProbe? emotionProbe,
  });
}

class RealBaselineMeasurementService implements BaselineMeasurementService {
  /// Warm-up samples that are read but NOT counted. They give the filter history
  /// to settle and let an initially elevated heart rate (e.g. the user just sat
  /// down or is tense) drift down before we start recording — so the baseline
  /// reflects a calmer resting rate, not the first jittery readings.
  static const int _settleSamples = 4;
  static const int _measureSamples = 8;
  static const int _minStable = 3;
  static const Duration _interval = Duration(milliseconds: 700);

  /// Emotion-probe tuning: a frame counts as a real face above this confidence,
  /// and the baseline is judged "not calm" when at least this fraction of the
  /// seen faces are an agitated (negative-valence) emotion.
  static const double _faceConfidence = 35;
  static const double _notCalmRatio = 0.5;
  static const Duration _emotionInterval = Duration(milliseconds: 1200);
  static const Set<String> _agitated = {'Angry', 'Fear', 'Sad', 'Disgust'};

  static int get _total => _settleSamples + _measureSamples;

  @override
  Future<BaselineResult> measure({
    void Function(int currentBpm, double progress)? onTick,
    BaselineEmotionProbe? emotionProbe,
  }) async {
    final service = createSensorService(timeout: const Duration(seconds: 3));
    final filter = SensorFilter();
    final stable = <int>[];

    // Sample the camera emotion in parallel so it never slows the HR loop.
    final emotions = <EmotionResult>[];
    var stopEmotion = false;
    final emotionRun =
        _sampleEmotions(emotionProbe, emotions, () => stopEmotion);

    for (var i = 0; i < _total; i++) {
      try {
        final raw = await service.fetchReading();
        final p = filter.process(raw);
        final settling = i < _settleSamples;
        // Accept any real BPM the filter is willing to report (it already
        // validates and smooths the value). We only reject when there's no
        // finger or no usable reading at all — requiring a perfect "GOOD"
        // signal made the baseline fail on the emulator and on briefly
        // unstable real sensors. Settling samples are shown but not recorded.
        if (!settling && p.hr > 0 && p.sensorQuality != 'NO FINGER') {
          stable.add(p.hr);
        }
        onTick?.call(p.hr, (i + 1) / _total);
      } catch (_) {
        // Skip this sample; a few misses are tolerated.
      }
      if (i < _total - 1) await Future.delayed(_interval);
    }

    stopEmotion = true;
    await emotionRun;
    final calmness = _judgeCalmness(emotions);

    if (stable.length < _minStable) {
      return (ok: false, bpm: null, calmness: calmness);
    }
    stable.sort();
    final mid = stable.length ~/ 2;
    final median = stable.length.isOdd
        ? stable[mid]
        : ((stable[mid - 1] + stable[mid]) / 2).round();
    return (ok: true, bpm: median, calmness: calmness);
  }

  /// Polls the probe roughly once a second until [stillRunning] turns false,
  /// collecting the clear-face emotions into [out].
  Future<void> _sampleEmotions(
    BaselineEmotionProbe? probe,
    List<EmotionResult> out,
    bool Function() stillRunning,
  ) async {
    if (probe == null) return;
    await probe.start();
    try {
      while (stillRunning()) {
        final e = await probe.sample();
        if (e != null) out.add(e);
        if (!stillRunning()) break;
        await Future.delayed(_emotionInterval);
      }
    } finally {
      await probe.stop();
    }
  }

  BaselineCalmness _judgeCalmness(List<EmotionResult> samples) {
    final faces =
        samples.where((e) => e.confidence >= _faceConfidence).toList();
    if (faces.length < 2) return BaselineCalmness.unknown; // not enough to judge
    final agitated = faces.where((e) => _agitated.contains(e.label)).length;
    return agitated / faces.length >= _notCalmRatio
        ? BaselineCalmness.notCalm
        : BaselineCalmness.calm;
  }
}

/// Simulates a quick baseline. Defaults to a calm 74 BPM; override [succeed] or
/// [calmness] to exercise the failure / not-calm paths in tests.
class MockBaselineMeasurementService implements BaselineMeasurementService {
  final int bpm;
  final bool succeed;
  final Duration tick;
  final BaselineCalmness calmness;

  const MockBaselineMeasurementService({
    this.bpm = 74,
    this.succeed = true,
    this.tick = Duration.zero,
    this.calmness = BaselineCalmness.unknown,
  });

  @override
  Future<BaselineResult> measure({
    void Function(int currentBpm, double progress)? onTick,
    BaselineEmotionProbe? emotionProbe,
  }) async {
    for (var i = 1; i <= 5; i++) {
      if (tick != Duration.zero) await Future.delayed(tick);
      onTick?.call(bpm - (5 - i), i / 5);
    }
    return succeed
        ? (ok: true, bpm: bpm, calmness: calmness)
        : (ok: false, bpm: null, calmness: calmness);
  }
}
