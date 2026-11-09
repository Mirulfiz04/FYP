import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../ui_kit.dart';

/// A compact summary metric (Total Users, Active Sessions, …). The [footer] is
/// supplied by the caller so the same card can show a trend pill, a "+N new"
/// badge or a health status dot.
class DashboardMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final Widget footer;

  const DashboardMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: color, size: 19),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: MedsColors.muted,
                      height: 1.1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                height: 1.0,
              ),
            ),
          ),
          const SizedBox(height: 6),
          footer,
        ],
      ),
    );
  }
}

/// Up/down percentage pill ("↑ 12% vs last 7d").
///
/// [higherIsBetter] controls the colour semantics: for metrics where a rise is
/// good (users, completion) an up-arrow is green; for metrics where a rise is
/// concerning (stress, flagged sessions) set it to false so up reads red.
class MetricTrendPill extends StatelessWidget {
  final double percent;
  final bool hasBaseline;
  final String comparison;
  final bool higherIsBetter;

  const MetricTrendPill({
    super.key,
    required this.percent,
    required this.hasBaseline,
    required this.comparison,
    this.higherIsBetter = true,
  });

  @override
  Widget build(BuildContext context) {
    final up = percent >= 0;
    final good = up == higherIsBetter;
    final color = good ? MedsColors.greenDark : MedsColors.red;
    final text = !hasBaseline
        ? 'New'
        : '${up ? '↑' : '↓'} ${percent.abs().toStringAsFixed(0)}%';
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(text,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.bold, fontSize: 11)),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(comparison,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: MedsColors.muted, fontSize: 11)),
        ),
      ],
    );
  }
}

/// "+N new" badge used by the AI Alerts card.
class MetricNewPill extends StatelessWidget {
  final int count;
  final String comparison;

  const MetricNewPill({super.key, required this.count, required this.comparison});

  @override
  Widget build(BuildContext context) {
    final color = count > 0 ? MedsColors.red : MedsColors.muted;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(count > 0 ? '↑ $count' : '0 new',
              style: TextStyle(
                  color: color, fontWeight: FontWeight.bold, fontSize: 11)),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(comparison,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: MedsColors.muted, fontSize: 11)),
        ),
      ],
    );
  }
}

/// Coloured dot + status word, reused by the System Health card.
class SystemStatusIndicator extends StatelessWidget {
  final Color color;
  final String label;

  const SystemStatusIndicator(
      {super.key, required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 7),
        Flexible(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w700, fontSize: 12.5)),
        ),
      ],
    );
  }
}

/// A gently pulsing grey placeholder used by the loading skeletons.
class SkeletonBox extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius? radius;

  const SkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.radius,
  });

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.10)
        : const Color(0xFF1B2333).withValues(alpha: 0.07);
    return FadeTransition(
      opacity: Tween(begin: 0.45, end: 1.0).animate(_c),
      child: Container(
        width: widget.width == double.infinity ? null : widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: base,
          borderRadius: widget.radius ?? BorderRadius.circular(8),
        ),
      ),
    );
  }
}

/// Skeleton placeholder shaped like a [DashboardMetricCard].
class MetricSkeletonCard extends StatelessWidget {
  const MetricSkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: const [
          Row(children: [
            SkeletonBox(width: 35, height: 35),
            SizedBox(width: 9),
            Expanded(child: SkeletonBox(width: double.infinity, height: 10)),
          ]),
          SizedBox(height: 14),
          SkeletonBox(width: 56, height: 22),
          SizedBox(height: 10),
          SkeletonBox(width: 90, height: 10),
        ],
      ),
    );
  }
}
