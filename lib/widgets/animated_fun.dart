import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A collection of small, dependency-free animations that make MEDS feel
/// lively and fun. Everything here is self-contained (each widget owns its
/// own ticker) so it can be dropped anywhere without extra setup.

/// Fades + slides a child up into place on first build. Use a staggered
/// [delay] on a list of widgets to get a pleasing cascade.
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final double offset;

  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = 0.10,
  });

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset(0, widget.offset),
          end: Offset.zero,
        ).animate(curved),
        child: widget.child,
      ),
    );
  }
}

/// A number that smoothly rolls from its previous value to [value] whenever
/// it changes (counts up from 0 on first appearance).
class AnimatedCount extends StatelessWidget {
  final int value;
  final TextStyle? style;
  final String prefix;
  final String suffix;
  final Duration duration;

  const AnimatedCount({
    super.key,
    required this.value,
    this.style,
    this.prefix = '',
    this.suffix = '',
    this.duration = const Duration(milliseconds: 650),
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (_, v, __) =>
          Text('$prefix${v.round()}$suffix', style: style),
    );
  }
}

/// A soft, continuously breathing radial glow placed behind an emoji/icon.
/// The [color] is supplied by the caller (e.g. the current emotion colour).
class PulseGlow extends StatefulWidget {
  final Color color;
  final double size;
  final Widget child;

  const PulseGlow({
    super.key,
    required this.color,
    required this.child,
    this.size = 170,
  });

  @override
  State<PulseGlow> createState() => _PulseGlowState();
}

class _PulseGlowState extends State<PulseGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_c.value);
        return Container(
          width: widget.size,
          height: widget.size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                widget.color.withValues(alpha: 0.28 + 0.22 * t),
                widget.color.withValues(alpha: 0.0),
              ],
              stops: const [0.05, 1.0],
            ),
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Shows an emoji that "pops" with an elastic bounce whenever it changes.
class AnimatedEmoji extends StatelessWidget {
  final String emoji;
  final double size;

  const AnimatedEmoji({super.key, required this.emoji, this.size = 76});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      switchInCurve: Curves.elasticOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, anim) => ScaleTransition(
        scale: anim,
        child: FadeTransition(opacity: anim, child: child),
      ),
      child: Text(
        emoji,
        key: ValueKey(emoji),
        style: TextStyle(fontSize: size),
      ),
    );
  }
}

/// A heart icon that beats in time with the given [bpm]. When [bpm] is 0 or
/// negative the heart stays still (no reading yet).
class PulsingHeart extends StatefulWidget {
  final int bpm;
  final Color color;
  final double size;

  const PulsingHeart({
    super.key,
    required this.bpm,
    this.color = const Color(0xFFFF4040),
    this.size = 30,
  });

  @override
  State<PulsingHeart> createState() => _PulsingHeartState();
}

class _PulsingHeartState extends State<PulsingHeart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: _period)..repeat();

  Duration get _period {
    final bpm = widget.bpm.clamp(40, 200);
    return Duration(milliseconds: (60000 / bpm).round());
  }

  @override
  void didUpdateWidget(covariant PulsingHeart old) {
    super.didUpdateWidget(old);
    if (old.bpm != widget.bpm) {
      _c.duration = _period;
      _c
        ..reset()
        ..repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.bpm <= 0) {
      return Icon(Icons.favorite, color: widget.color, size: widget.size);
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        // Two quick thumps (lub-dub) then a rest, like a real heartbeat.
        final t = _c.value;
        double thump(double at) =>
            math.exp(-math.pow((t - at) * 9, 2).toDouble());
        final pulse = 1.0 + 0.32 * thump(0.10) + 0.20 * thump(0.26);
        return Transform.scale(
          scale: pulse.clamp(1.0, 1.6),
          child: Icon(Icons.favorite, color: widget.color, size: widget.size),
        );
      },
    );
  }
}

/// A friendly hand that waves a few times, pauses, then waves again.
class WavingHand extends StatefulWidget {
  final double size;
  const WavingHand({super.key, this.size = 24});

  @override
  State<WavingHand> createState() => _WavingHandState();
}

class _WavingHandState extends State<WavingHand>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        // Wave only during the first third of the cycle, then rest.
        final t = _c.value;
        final wave = t < 0.33 ? math.sin(t / 0.33 * math.pi * 4) : 0.0;
        return Transform.rotate(
          angle: wave * 0.35,
          alignment: Alignment.bottomCenter,
          child: Text('👋', style: TextStyle(fontSize: widget.size)),
        );
      },
    );
  }
}

/// Fires a short burst of confetti from the centre whenever [trigger]
/// increments. Place it inside a [Stack] (e.g. via Positioned.fill).
class ConfettiBurst extends StatefulWidget {
  final int trigger;
  const ConfettiBurst({super.key, required this.trigger});

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  final _rng = math.Random();
  List<_Particle> _particles = const [];

  static const _palette = [
    Color(0xFF00DC64),
    Color(0xFF00B4FF),
    Color(0xFF9B30FF),
    Color(0xFFFFA500),
    Color(0xFFFF4D6D),
    Color(0xFFFFE000),
  ];

  @override
  void didUpdateWidget(covariant ConfettiBurst old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger && widget.trigger > 0) _fire();
  }

  void _fire() {
    _particles = List.generate(30, (_) {
      return _Particle(
        angle: _rng.nextDouble() * 2 * math.pi,
        speed: 90 + _rng.nextDouble() * 190,
        size: 6 + _rng.nextDouble() * 9,
        color: _palette[_rng.nextInt(_palette.length)],
        rotation: _rng.nextDouble() * 2 * math.pi,
        rotationSpeed: (_rng.nextDouble() - 0.5) * 10,
      );
    });
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => CustomPaint(
          painter: _ConfettiPainter(
            _particles,
            Curves.easeOut.transform(_c.value),
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _Particle {
  final double angle;
  final double speed;
  final double size;
  final Color color;
  final double rotation;
  final double rotationSpeed;

  const _Particle({
    required this.angle,
    required this.speed,
    required this.size,
    required this.color,
    required this.rotation,
    required this.rotationSpeed,
  });
}

class _ConfettiPainter extends CustomPainter {
  final List<_Particle> particles;
  final double t; // 0..1

  _ConfettiPainter(this.particles, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1 || particles.isEmpty) return;
    const gravity = 260.0;
    final origin = Offset(size.width / 2, size.height * 0.42);
    final opacity = (1.0 - t).clamp(0.0, 1.0);

    for (final p in particles) {
      final dx = math.cos(p.angle) * p.speed * t;
      final dy =
          math.sin(p.angle) * p.speed * t + 0.5 * gravity * t * t;
      final pos = origin + Offset(dx, dy);
      final paint = Paint()..color = p.color.withValues(alpha: opacity);
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(p.rotation + p.rotationSpeed * t);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: p.size,
            height: p.size * 0.6,
          ),
          const Radius.circular(2),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
