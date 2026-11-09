import 'dart:collection';
import 'dart:math' as math;

/// One face-detector reading: ML Kit head pose (degrees) plus the eyes-open
/// and smiling probabilities (0..1). Any field is null when ML Kit doesn't
/// report it for that frame.
class FaceFrame {
  /// headEulerAngleX — positive = facing up, negative = head down.
  final double? pitch;

  /// headEulerAngleY — turned left/right.
  final double? yaw;

  /// headEulerAngleZ — tilted sideways.
  final double? roll;
  final double? leftEyeOpen;
  final double? rightEyeOpen;
  final double? smile;

  const FaceFrame({
    this.pitch,
    this.yaw,
    this.roll,
    this.leftEyeOpen,
    this.rightEyeOpen,
    this.smile,
  });
}

/// "Body language" from the face detector the app already runs: keeps the last
/// [window] of [FaceFrame]s and derives three sustained cues — head held down,
/// restlessness and eye closure.
///
/// These are heuristics, not a trained model: there is no labelled data to
/// measure them, so the fusion only lets them nudge the emotion mildly. The
/// camera is a front camera framed on the face, so this is head/eye language,
/// not full-body pose.
class BodyCues {
  /// How far back the cues look. Frames arrive every ~1.5 s, so ~6 frames.
  static const Duration window = Duration(seconds: 10);

  /// Frames needed before a cue can fire: ~6 s of face at 1.5 s/frame, so a
  /// quick glance or a single odd frame never counts as "sustained".
  static const int minFrames = 4;

  /// Share of the window's frames that must show a cue. With ~6 frames, 4 must
  /// agree, so one or two outliers (detector jitter, a blink) don't fire it.
  static const double sustainedShare = 0.6;

  /// Pitch at/below this (degrees) counts as head down. Looking at the phone
  /// keeps the face pointed at the camera (pitch near 0); -15° is a clear drop,
  /// well past ML Kit's few-degree jitter and glancing at the screen's edge.
  static const double headDownPitch = -15;

  /// Mean head speed (°/s over pitch+yaw+roll) at/above which we call it
  /// restless. Detector jitter on a still head is ~1–2 °/s at this frame rate,
  /// and normal talking/nodding stays below ~4 °/s; 6 °/s means the head keeps
  /// shifting. A guess to tune on real sessions.
  static const double restlessDegPerSec = 6;

  /// Mean eyes-open probability below this counts as closed/drooping. Open eyes
  /// read ~0.8–1.0; 0.3 leaves room for narrow eyes and glasses.
  static const double eyesClosedProb = 0.3;

  /// ML Kit's eyes-open/smile values only hold for frontal faces (its docs say
  /// |yaw| < 18°), so a turned head must not read as closed eyes.
  static const double _frontalYaw = 18;

  final Queue<(DateTime, FaceFrame)> _frames = Queue();

  void add(FaceFrame frame, {DateTime? at}) {
    final now = at ?? DateTime.now();
    _frames.addLast((now, frame));
    while (now.difference(_frames.first.$1) > window) {
      _frames.removeFirst();
    }
  }

  /// Head held down for most of the window.
  bool get headDown =>
      _sustained((f) => f.pitch == null ? null : f.pitch! <= headDownPitch);

  /// Eyes mostly closed/drooping over the window — fatigue. A blink lasts
  /// ~0.15 s, so 1.5 s-spaced frames catch one only ~5% of the time.
  bool get eyesClosing => _sustained((f) {
        final l = f.leftEyeOpen, r = f.rightEyeOpen, yaw = f.yaw;
        if (l == null || r == null) return null;
        if (yaw != null && yaw.abs() >= _frontalYaw) return null;
        return (l + r) / 2 < eyesClosedProb;
      });

  /// Mean head speed over the window in °/s: total angular path between
  /// consecutive frames divided by the time they span. 0 with too few frames.
  double get restlessness {
    final posed = [
      for (final (t, f) in _frames)
        if (f.pitch != null && f.yaw != null && f.roll != null) (t, f)
    ];
    if (posed.length < minFrames) return 0;
    var path = 0.0;
    for (var i = 1; i < posed.length; i++) {
      final a = posed[i - 1].$2, b = posed[i].$2;
      path += math.sqrt(math.pow(b.pitch! - a.pitch!, 2) +
          math.pow(b.yaw! - a.yaw!, 2) +
          math.pow(b.roll! - a.roll!, 2));
    }
    final seconds =
        posed.last.$1.difference(posed.first.$1).inMilliseconds / 1000;
    return seconds > 0 ? path / seconds : 0;
  }

  bool get restless => restlessness >= restlessDegPerSec;

  /// Live-insight text for the strongest current cue, or null when none holds.
  String? get insight {
    if (restless) return 'You seem restless — try a slow breath.';
    if (eyesClosing) return 'Your eyes look tired — a short break might help.';
    if (headDown) {
      return 'Your head has been down for a while — try sitting up and '
          'relaxing your shoulders.';
    }
    return null;
  }

  /// True when at least [minFrames] frames report the value and
  /// [sustainedShare] of them pass [test] (null = not reported, skipped).
  bool _sustained(bool? Function(FaceFrame) test) {
    var seen = 0, hits = 0;
    for (final (_, f) in _frames) {
      final r = test(f);
      if (r == null) continue;
      seen++;
      if (r) hits++;
    }
    return seen >= minFrames && hits >= seen * sustainedShare;
  }
}
