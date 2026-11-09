import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'ui_kit.dart';

/// One component-status item.
class ConnStatus {
  final String label;
  final String status;
  final Color color;
  final IconData icon;
  const ConnStatus({
    required this.label,
    required this.status,
    required this.color,
    required this.icon,
  });
}

/// The three small status cards: Camera, Heart-rate Sensor, Signal Quality.
class ConnectionStatusCards extends StatelessWidget {
  final ConnStatus camera;
  final ConnStatus sensor;
  final ConnStatus signal;

  const ConnectionStatusCards({
    super.key,
    required this.camera,
    required this.sensor,
    required this.signal,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _card(camera)),
        const SizedBox(width: 10),
        Expanded(child: _card(sensor)),
        const SizedBox(width: 10),
        Expanded(child: _card(signal)),
      ],
    );
  }

  Widget _card(ConnStatus s) {
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                    color: MedsColors.purple.withValues(alpha: 0.12),
                    shape: BoxShape.circle),
                child: Icon(s.icon, color: MedsColors.purple, size: 17),
              ),
              const Spacer(),
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: s.color, shape: BoxShape.circle),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(s.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: MedsColors.muted, fontSize: 11.5)),
          const SizedBox(height: 2),
          Text(s.status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: s.color, fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }
}
