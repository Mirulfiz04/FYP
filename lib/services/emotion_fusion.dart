import 'dart:collection';
import '../models/emotion_result.dart';
import '../models/multimodal_result.dart';
import '../models/sensor_reading.dart';
import 'body_cues.dart';

/// Combines the camera emotion with the ESP32 heart rate into one multimodal
/// read-out.
///
/// Two steps:
///  1. **Temporal smoothing** — averages the facial probabilities over the last
///     few frames so the displayed emotion stops flickering frame-to-frame.
///  2. **Late fusion** — uses heart-rate change from a per-session baseline as
///     an *arousal* signal that nudges the facial probabilities (high arousal
///     favours anger/fear/surprise; low arousal favours calm/disgust/sad), then
///     derives a wellbeing state from valence (face) × arousal (HR).
///
/// HR only *corroborates* the face — the weights are deliberately modest so a
/// confident facial reading is never overridden, which matches reality: HR
/// alone can't tell anger from fear, and is weak/inconsistent for happiness.
class EmotionFusion {
  static const int _smoothWindow = 4;
  static const int _baselineNeeded = 8; // valid HR samples before a baseline
  static const int _restingWindow = 60; // ~60s of recent valid HRs
  static const double _restingPercentile = 0.20; // "sustained low" floor

  // --- Reliability-weighted fusion + hysteresis ----------------------------
  // A new top emotion must stay on top for [_commitFrames] frames AND clear
  // [_commitFloor] before it replaces the emitted one. On top of the 4-frame
  // probability smoothing, this stops the label flipping on a single bad frame.
  static const int _commitFrames = 2;
  static const double _commitFloor = 0.45;
  // Face certainty at/above which HR stops nudging the label (a confident face
  // is never overridden); below it, HR's influence scales up.
  static const double _confMid = 0.5;

  // --- Voice check-in ("Are you OK?") ---------------------------------------
  // A spoken answer is blended into the face for a while after it is given.
  // Voice alone is less accurate than the face, so it never takes over: at most
  // [_voiceMaxWeight] of the blend, fading linearly to 0 over [_voiceHold].
  static const Duration _voiceHold = Duration(seconds: 20);
  static const double _voiceMaxWeight = 0.4;
  List<double>? _voiceProbs; // in face-label order
  DateTime? _voiceAt;

  // --- Body cues (head pose / restlessness, see BodyCues) -------------------
  // Unmeasured heuristics, so a sustained cue that agrees with the HR arousal
  // moves at most [_cueMaxWeight] of the probability mass onto one emotion —
  // the same cap idea as [_voiceMaxWeight], but smaller.
  static const double _cueMaxWeight = 0.1;

  final Queue<List<double>> _probHistory = Queue<List<double>>();
  final List<int> _initialSamples = []; // warm-up median when not seeded
  final Queue<int> _hrWindow = Queue<int>(); // rolling window for the floor
  int? _baselineHr;

  // Hysteresis state for the emitted label.
  String? _committedLabel;
  String? _candidateLabel;
  int _candidateCount = 0;

  /// [seedBaselineBpm] seeds the resting baseline with the pre-session reading
  /// from the readiness screen, so arousal works from the first frame instead of
  /// needing an 8-sample warm-up. It still adapts down from there.
  EmotionFusion({int? seedBaselineBpm})
      : _baselineHr =
            (seedBaselineBpm != null && seedBaselineBpm > 0) ? seedBaselineBpm : null;

  /// The effective resting baseline currently in use (for tests / telemetry).
  int? get baselineHr => _baselineHr;

  // Labels are produced capitalised by the classifier:
  // Surprise, Sad, Neutral, Happy, Fear, Disgust, Angry.
  static const Set<String> _highArousal = {'Angry', 'Fear', 'Surprise'};
  static const Set<String> _lowArousal = {'Disgust', 'Sad'};

  /// Feeds a voice check-in result. [voiceLabels] is the voice model's output
  /// order; it is re-ordered to [faceLabels] so the two can be blended.
  void addVoice(List<double> probs, List<String> voiceLabels,
      List<String> faceLabels, {DateTime? at}) {
    if (faceLabels.isEmpty) return;
    _voiceProbs = faceLabels.map((l) {
      final i = voiceLabels.indexOf(l);
      return i >= 0 && i < probs.length ? probs[i] : 0.0;
    }).toList();
    _voiceAt = at ?? DateTime.now();
  }

  /// "Says OK but sounds stressed": the face reads neutral/positive while a
  /// confident voice result reads clearly negative. Returns the voice emotion,
  /// or null when face and voice agree.
  static String? voiceMismatch(String faceLabel, EmotionResult voice,
      {double minConfidence = 50}) {
    if (voice.confidence < minConfidence) return null;
    return valenceOf(faceLabel) >= 0 && valenceOf(voice.label) < -0.25
        ? voice.label
        : null;
  }

  MultimodalResult process(
    EmotionResult facial,
    List<String> labels,
    ProcessedSensorReading sensor, {
    DateTime? now,
    BodyCues? body,
  }) {
    // 1. Smooth the facial probabilities over the recent window, then blend in
    //    a recent voice check-in (if any).
    _probHistory.addLast(List<double>.from(facial.probabilities));
    while (_probHistory.length > _smoothWindow) {
      _probHistory.removeFirst();
    }
    final smoothed = _blendVoice(_averaged(), now ?? DateTime.now());

    // 2. How much do we trust the HR this frame? (from the sensor quality)
    final hrReliability = _hrReliability(sensor.sensorQuality);

    // 3. Establish the resting baseline and read current arousal. Both ignore
    //    unreliable HR so a bad/held signal can't invent arousal.
    _updateBaseline(sensor, hrReliability);
    final arousal = _arousal(sensor, hrReliability);

    // 4. Late fusion, scaled by reliability. HR nudges the label only as much
    //    as (a) its signal is trustworthy and (b) the face is uncertain — a
    //    confident face is left essentially alone.
    final faceTop =
        smoothed.isEmpty ? 0.0 : smoothed.reduce((a, b) => a > b ? a : b);
    final faceUncertainty =
        (1.0 - (faceTop - _confMid) / (1.0 - _confMid)).clamp(0.0, 1.0);
    final strength = hrReliability * faceUncertainty;
    final fused = _applyBodyCues(
        _applyHrWeights(smoothed, labels, arousal.level, strength),
        labels,
        arousal.level,
        body);

    // 5. Raw top emotion, then the hysteresis-committed label we actually emit.
    var best = 0;
    for (var i = 1; i < fused.length; i++) {
      if (fused[i] > fused[best]) best = i;
    }
    final rawLabel = best < labels.length ? labels[best] : 'Unknown';
    final label = _commit(rawLabel, fused, labels);
    final labelIdx = labels.indexOf(label);
    final confidence = (labelIdx >= 0 && labelIdx < fused.length)
        ? fused[labelIdx]
        : (fused.isEmpty ? 0.0 : fused[best]);

    // 6. Valence (committed face) × arousal (HR) → wellbeing state.
    final valence = valenceOf(label);
    final wb = _wellbeing(valence, arousal.level);

    return MultimodalResult(
      emotion: EmotionResult(
        label: label,
        confidence: confidence * 100.0,
        probabilities: fused,
      ),
      arousal: arousal.level,
      hrDelta: arousal.delta,
      baselineReady: _baselineHr != null,
      baselineBpm: _baselineHr,
      wellbeing: wb.name,
      wellbeingEmoji: wb.emoji,
      valence: valence,
    );
  }

  /// Maps sensor quality → how much we trust the HR this frame (0..1).
  double _hrReliability(String quality) {
    switch (quality) {
      case 'GOOD':
        return 1.0;
      case 'HOLDING HR':
        return 0.5;
      default: // WAITING, NO FINGER, BAD SIGNAL
        return 0.0;
    }
  }

  /// Stabilises the emitted label: a new emotion must stay on top for
  /// [_commitFrames] frames AND clear [_commitFloor] before it replaces the
  /// current one. Prevents single-frame flips.
  String _commit(String rawLabel, List<double> fused, List<String> labels) {
    if (_committedLabel == null) {
      _committedLabel = rawLabel;
      _candidateLabel = null;
      _candidateCount = 0;
      return _committedLabel!;
    }
    if (rawLabel == _committedLabel) {
      _candidateLabel = null;
      _candidateCount = 0;
      return _committedLabel!;
    }
    final idx = labels.indexOf(rawLabel);
    final conf = (idx >= 0 && idx < fused.length) ? fused[idx] : 0.0;
    if (conf < _commitFloor) {
      // Too weak to challenge the committed label — keep what we have.
      _candidateLabel = null;
      _candidateCount = 0;
      return _committedLabel!;
    }
    if (rawLabel == _candidateLabel) {
      _candidateCount++;
    } else {
      _candidateLabel = rawLabel;
      _candidateCount = 1;
    }
    if (_candidateCount >= _commitFrames) {
      _committedLabel = rawLabel;
      _candidateLabel = null;
      _candidateCount = 0;
    }
    return _committedLabel!;
  }

  List<double> _blendVoice(List<double> face, DateTime now) {
    final voice = _voiceProbs, at = _voiceAt;
    if (voice == null || at == null || voice.length != face.length) return face;
    final age = now.difference(at);
    if (age.isNegative || age >= _voiceHold) return face;
    final w = _voiceMaxWeight *
        (1 - age.inMilliseconds / _voiceHold.inMilliseconds);
    return [
      for (var i = 0; i < face.length; i++) (1 - w) * face[i] + w * voice[i]
    ];
  }

  List<double> _averaged() {
    if (_probHistory.isEmpty) return const [];
    final n = _probHistory.first.length;
    final sum = List<double>.filled(n, 0.0);
    for (final p in _probHistory) {
      for (var i = 0; i < n && i < p.length; i++) {
        sum[i] += p[i];
      }
    }
    return sum.map((e) => e / _probHistory.length).toList();
  }

  /// Establishes the resting baseline and then adapts it *downward* toward the
  /// user's sustained resting rate during the session. Ratchet-down-only on
  /// purpose: a baseline captured while the user was tense reads too high and
  /// would mask real stress; letting it fall toward the observed resting floor
  /// self-corrects that. We never let stress *raise* the baseline.
  void _updateBaseline(ProcessedSensorReading s, double reliability) {
    // Only learn the baseline from a trustworthy signal (GOOD/HOLDING), so a
    // bad-signal frame can't pollute the resting rate.
    if (s.hr <= 0 || reliability < 0.5) return;

    // No seed → establish an initial baseline from the first valid samples.
    if (_baselineHr == null) {
      _initialSamples.add(s.hr);
      if (_initialSamples.length >= _baselineNeeded) {
        final sorted = [..._initialSamples]..sort();
        _baselineHr = sorted[sorted.length ~/ 2]; // median resting HR
      }
    }

    // Keep a rolling window of recent HRs and ratchet the baseline down toward
    // its low (sustained-resting) percentile.
    _hrWindow.addLast(s.hr);
    while (_hrWindow.length > _restingWindow) {
      _hrWindow.removeFirst();
    }
    if (_baselineHr != null && _hrWindow.length >= _baselineNeeded) {
      final floor = _percentile(_hrWindow.toList(), _restingPercentile);
      if (floor > 0 && floor < _baselineHr!) _baselineHr = floor;
    }
  }

  int _percentile(List<int> values, double p) {
    if (values.isEmpty) return 0;
    final sorted = [...values]..sort();
    final idx = (p * (sorted.length - 1)).round().clamp(0, sorted.length - 1);
    return sorted[idx];
  }

  _ArousalInfo _arousal(ProcessedSensorReading s, double reliability) {
    final base = _baselineHr;
    if (base == null || s.hr <= 0 || reliability <= 0.0) {
      return const _ArousalInfo(Arousal.normal, 0);
    }
    final delta = s.hr - base;
    if (delta >= 12) return _ArousalInfo(Arousal.high, delta);
    if (delta >= 5) return _ArousalInfo(Arousal.elevated, delta);
    if (delta <= -4) return _ArousalInfo(Arousal.low, delta);
    return _ArousalInfo(Arousal.normal, delta);
  }

  List<double> _applyHrWeights(
    List<double> probs,
    List<String> labels,
    Arousal level,
    double strength,
  ) {
    // strength == 0 → no reliable HR / very confident face: leave the face
    // distribution untouched.
    if (probs.isEmpty || strength <= 0) return probs;
    final weighted = <double>[];
    for (var i = 0; i < probs.length; i++) {
      final lbl = i < labels.length ? labels[i] : '';
      // Scale each class weight's deviation from 1.0 by the fusion strength.
      final eff = 1.0 + (_weightFor(lbl, level) - 1.0) * strength;
      weighted.add(probs[i] * eff);
    }
    final total = weighted.fold<double>(0.0, (a, b) => a + b);
    if (total <= 0) return probs;
    return weighted.map((e) => e / total).toList();
  }

  /// HR arousal can't separate Sad from Neutral, or Fear from Angry/Surprise;
  /// a sustained body cue that agrees with it breaks that tie. Head held down +
  /// HR below baseline → Sad; restless + HR above baseline → Fear. Neither cue
  /// moves anything on its own. Eye closure (fatigue) is no face class, so it
  /// only drives the live insight.
  List<double> _applyBodyCues(
    List<double> probs,
    List<String> labels,
    Arousal level,
    BodyCues? body,
  ) {
    if (body == null || probs.isEmpty) return probs;
    final target = body.headDown && level == Arousal.low
        ? 'Sad'
        : body.restless &&
                (level == Arousal.high || level == Arousal.elevated)
            ? 'Fear'
            : null;
    final t = target == null ? -1 : labels.indexOf(target);
    if (t < 0 || t >= probs.length) return probs;
    return [
      for (var i = 0; i < probs.length; i++)
        (1 - _cueMaxWeight) * probs[i] + (i == t ? _cueMaxWeight : 0.0)
    ];
  }

  double _weightFor(String label, Arousal level) {
    final high = _highArousal.contains(label);
    final low = _lowArousal.contains(label) || label == 'Neutral';
    switch (level) {
      case Arousal.high:
        if (high) return 1.35;
        if (low) return 0.85;
        return 1.0;
      case Arousal.elevated:
        if (high) return 1.15;
        if (low) return 0.95;
        return 1.0;
      case Arousal.low:
        if (high) return 0.8;
        if (low) return 1.15;
        return 1.0;
      case Arousal.normal:
        return 1.0;
    }
  }

  static double valenceOf(String label) {
    switch (label) {
      case 'Happy':
        return 1.0;
      case 'Surprise':
        return 0.5;
      case 'Sad':
        return -0.7;
      case 'Disgust':
        return -0.6;
      case 'Fear':
        return -0.8;
      case 'Angry':
        return -1.0;
      default:
        return 0.0; // Neutral / Unknown
    }
  }

  _Wellbeing _wellbeing(double valence, Arousal arousal) {
    final highAr = arousal == Arousal.high || arousal == Arousal.elevated;
    final lowAr = arousal == Arousal.low;
    if (valence > 0.25) {
      return highAr
          ? const _Wellbeing('Excited', '🤩')
          : const _Wellbeing('Content', '😊');
    }
    if (valence < -0.25) {
      return highAr
          ? const _Wellbeing('Stressed', '😣')
          : const _Wellbeing('Down', '😔');
    }
    if (highAr) return const _Wellbeing('Alert', '😯');
    if (lowAr) return const _Wellbeing('Relaxed', '😌');
    return const _Wellbeing('Calm', '🙂');
  }
}

class _ArousalInfo {
  final Arousal level;
  final int delta;
  const _ArousalInfo(this.level, this.delta);
}

class _Wellbeing {
  final String name;
  final String emoji;
  const _Wellbeing(this.name, this.emoji);
}
